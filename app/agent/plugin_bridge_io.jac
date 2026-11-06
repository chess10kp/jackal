"""Plugin bridge stdio correlation and interactive UI transport."""

import json;
import threading;
import time;
import from .protocol { Envelope, make_envelope, is_plugin_kind }
import from .interactions { new_ui_queue, UiInteractionQueue }
import from .plugin_bridge_support { envelope_to_dict, envelope_from_dict }
import from .plugin_bridge_model { BridgeWaiter, PluginBridge }
import from _subprocess_native { sp_read, sp_write }
def:pub _node_alive_io(bridge: PluginBridge) -> bool {
    if bridge.host_kind != "node" or bridge.proc is None {
        return False;
    }
    return bridge.proc.poll() is None;
}

def:pub _write_node(bridge: PluginBridge, env: Envelope) {
    if not _node_alive_io(bridge) {
        raise RuntimeError("plugin node host not running");
    }
    line: bytes = (json.dumps(envelope_to_dict(env)) + "\n").encode("utf-8");
    lock: threading.Lock | None = bridge.write_lock;
    if lock is not None {
        lock.acquire();
        try {
            _write_node_bytes(bridge.stdin_fd, line);
        } finally {
            lock.release();
        }
    } else {
        _write_node_bytes(bridge.stdin_fd, line);
    }
}

def _write_node_bytes(fd: int, data: bytes) {
    off: int = 0;
    while off < len(data) {
        n: int = sp_write(fd, data[off:]);
        if n <= 0 {
            raise RuntimeError("plugin host stdin closed");
        }
        off += n;
    }
}

def _read_node_line(bridge: PluginBridge, fd: int) -> bytes {
    newline: int = bridge.reader_buffer.find(b"\n");
    while newline < 0 {
        chunk: bytes = sp_read(fd, 4096);
        if not chunk {
            line: bytes = bridge.reader_buffer;
            bridge.reader_buffer = b"";
            return line;
        }
        bridge.reader_buffer += chunk;
        newline = bridge.reader_buffer.find(b"\n");
    }
    line: bytes = bridge.reader_buffer[:newline];
    bridge.reader_buffer = bridge.reader_buffer[newline + 1:];
    return line;
}


"""Route an inbound envelope to a pending waiter; always keep a copy in inbox.

Kind-aware: a waiter registered with expect_kind only completes for that kind;
mismatched envelopes stay inbox-only so interleaved traffic (tool_update vs
tool_result, future ui_request children) cannot wake or consume the wrong
waiter."""
def:pub _dispatch_inbound(bridge: PluginBridge, env: Envelope) {
    # P12 interactive-UI traffic routes to the interaction queue, never to
    # parent waiters and never into the unbounded diagnostic inbox.
    if env.kind == "ui_request" {
        _ui_enqueue_from_env(bridge, env);
        return;
    }
    if env.kind == "ui_cancel" {
        q0: UiInteractionQueue | None = bridge.ui_q;
        if q0 is not None {
            q0.take(str(env.correlation_id));
        }
        return;
    }
    bridge.inbox.append(env);
    corr = env.correlation_id;
    pending: dict[str, BridgeWaiter] = bridge.pending;
    if corr and corr in pending {
        waiter: BridgeWaiter = pending[corr];
        if waiter.expect and waiter.expect != env.kind {
            return;
        }
        waiter.env = env;
        waiter.event.set();
    }
}


"""Background stdout reader — multiplexes replies by correlation_id (P3)."""
def:pub _reader_loop(bridge: PluginBridge) {
    stop: threading.Event | None = bridge.reader_stop;
    proc = bridge.proc;
    if proc is None or bridge.stdout_fd < 0 or stop is None {
        return;
    }
    while stop is None or not stop.is_set() {
        try {
            line_raw: bytes = _read_node_line(bridge, bridge.stdout_fd);
        } except Exception {
            break;
        }
        if not line_raw {
            break;
        }
        line_s: str = line_raw.decode("utf-8", errors="replace").strip();
        if not line_s {
            continue;
        }
        try {
            parsed: any = json.loads(line_s);
        } except Exception {
            bridge.inbox.append(
                make_envelope(
                    kind="host_status",
                    session_id=bridge.session_id,
                    payload={"phase": "degraded", "detail": "bad json from host"},
                )
            );
            continue;
        }
        if not isinstance(parsed, dict) {
            continue;
        }
        env = envelope_from_dict(parsed);
        _dispatch_inbound(bridge, env);
    }
}


def:pub _ensure_io(bridge: PluginBridge) {
    if bridge.write_lock is None {
        bridge.write_lock = threading.Lock();
    }
    if bridge.reader_stop is None {
        bridge.reader_stop = threading.Event();
    }
    if bridge.pending is None {
        bridge.pending = {};
    }
}


def:pub _start_reader(bridge: PluginBridge) {
    _ensure_io(bridge);
    if bridge.reader_thread is not None and bridge.reader_thread.is_alive() {
        return;
    }
    stop: threading.Event | None = bridge.reader_stop;
    if stop is None {
        return;
    }
    stop.clear();
    def read_bridge() {
        _reader_loop(bridge);
    }
    t = threading.Thread(
        target=read_bridge, daemon=True, name="plugin-host-reader"
    );
    bridge.reader_thread = t;
    t.start();
}


def:pub _stop_reader(bridge: PluginBridge) {
    if bridge.reader_stop is not None {
        bridge.reader_stop.set();
    }
    bridge.reader_thread = None;
}


"""Wait for a correlated reply (or any matching kind if corr empty).

Callers that write a request MUST register `correlation_id` in
`bridge.pending` *before* `_write_node` (or call `_prepare_corr`) so the
reader cannot win the race.
"""
def:pub _prepare_corr(
    bridge: PluginBridge, correlation_id: str, expect_kind: str = ""
) {
    _ensure_io(bridge);
    pending: dict[str, BridgeWaiter] = bridge.pending;
    if correlation_id and correlation_id not in pending {
        # expect_kind: only an envelope of this kind may complete the waiter.
        # Guards against sibling traffic (e.g. tool_update sharing the parent
        # correlation with tool_result) waking the wrong waiter.
        bridge.pending[correlation_id] = BridgeWaiter(
            event=threading.Event(), expect=expect_kind
        );
    }
}


def:pub _wait_corr(
    bridge: PluginBridge,
    kind: str,
    correlation_id: str = "",
    timeout: float = 5.0,
) -> Envelope {
    deadline = time.monotonic() + timeout;
    if correlation_id {
        _prepare_corr(bridge, correlation_id, expect_kind=kind);
        # UI lease (P12): while a correlated ui_request sits open for this
        # parent, the fixed handler budget is PAUSED — bounded by a
        # cumulative 600s lease measured from first grant. User think-time
        # must not kill the command/hook that asked the question.
        while True {
            waiter: BridgeWaiter | None = bridge.pending.get(correlation_id);
            if waiter is None {
                break;  # dispatcher consumed it without storing env
            }
            if waiter.env is not None {
                bridge.pending.pop(correlation_id, None);
                return waiter.env as Envelope;
            }
            if waiter.ui_lease_start > 0.0 {
                # Lease active: short polls only (honors the 600s cap and
                # keeps wakeups bounded to the interaction window).
                if time.monotonic() >= waiter.ui_lease_start + 600.0 {
                    bridge.pending.pop(correlation_id, None);
                    raise TimeoutError(f"timed out waiting for {kind}");
                }
                waiter.event.wait(timeout=0.05);
                continue;
            }
            remaining = max(0.01, deadline - time.monotonic());
            ok = waiter.event.wait(timeout=remaining);
            if ok {
                continue;  # dispatcher stored env; re-check at loop top
            }
            # Budget exhausted — grant a UI lease iff a correlated request
            # is still open (user think-time pauses the handler budget).
            q: UiInteractionQueue | None = bridge.ui_q;
            has_pending_ui = False;
            if q is not None {
                has_pending_ui = q.has_open(correlation_id);
            }
            if has_pending_ui {
                waiter.ui_lease_start = time.monotonic();
                continue;
            }
            bridge.pending.pop(correlation_id, None);
            raise TimeoutError(f"timed out waiting for {kind}");
        }
        raise TimeoutError(f"timed out waiting for {kind}");
    }
    # No corr: poll inbox for kind (do not remove — drain_inbox owns removal).
    while time.monotonic() < deadline {
        for i in range(len(bridge.inbox)) {
            env = bridge.inbox[i];
            if not kind or env.kind == kind {
                return env;
            }
        }
        time.sleep(0.02);
    }
    raise TimeoutError(f"timed out waiting for {kind}");
}


def:pub _read_node(bridge: PluginBridge, timeout: float = 5.0) -> Envelope {
    return _wait_corr(bridge, "", "", timeout=timeout);
}


"""Read until an envelope with kind matches (or timeout)."""
def:pub _read_node_until(
    bridge: PluginBridge, kind: str, correlation_id: str = "", timeout: float = 5.0
) -> Envelope {
    if correlation_id {
        env = _wait_corr(bridge, kind, correlation_id, timeout=timeout);
        if env.kind != kind {
            raise TimeoutError(f"timed out waiting for {kind}");
        }
        return env;
    }
    deadline = time.monotonic() + timeout;
    while time.monotonic() < deadline {
        remaining = max(0.05, deadline - time.monotonic());
        try {
            env = _wait_corr(bridge, kind, "", timeout=remaining);
            if env.kind == kind {
                return env;
            }
            bridge.inbox.append(env);
        } except TimeoutError {
            break;
        }
    }
    raise TimeoutError(f"timed out waiting for {kind}");
}


"""Spawn the Node plugin host. Emits host_hello from the child."""
def:pub _ui_queue(bridge: PluginBridge) -> UiInteractionQueue {
    if bridge.ui_q is None {
        bridge.ui_q = new_ui_queue();
    }
    return bridge.ui_q as UiInteractionQueue;
}


def:pub _ui_enqueue_from_env(bridge: PluginBridge, env: Envelope) {
    p = env.payload if env.payload is not None else {};
    req: dict[str, any] = {
        "corr": str(env.correlation_id or ""),
        "parent_corr": str(p.get("parent_correlation_id", "")),
        "parent_kind": str(p.get("parent_kind", "")),
        "extension_id": str(p.get("extension_id", "")),
        "method": str(p.get("method", "")),
        "title": str(p.get("title", "")),
        "message": str(p.get("message", "")),
        "options": p.get("options", []) if isinstance(p.get("options"), list) else [],
        "placeholder": str(p.get("placeholder", "")),
        "created": time.monotonic(),
        "timeout_ms": float(p.get("timeout_ms", 30000.0)),
    };
    q = _ui_queue(bridge);
    res = q.enqueue(req);
    if not res[0] {
        # Invalid request: tell Node immediately so its Promise settles.
        _ui_send_response(bridge, str(env.correlation_id), "cancelled", None, str(res[1]));
    }
}


def:pub _ui_send_response(
    bridge: PluginBridge, corr: str, status: str, value: any, reason: str = ""
) -> bool {
    payload: dict[str, any] = {"status": status};
    if value is not None {
        payload["value"] = value;
    }
    if reason {
        payload["reason"] = reason;
    }
    if bridge.host_kind == "node" and _node_alive_io(bridge) {
        try {
            _write_node(bridge, make_envelope(
                kind="ui_response",
                session_id=bridge.session_id,
                correlation_id=corr,
                payload=payload,
            ));
            return True;
        } except Exception {
            return False;
        }
    }
    return True;  # fake-host path: nothing to write
}
