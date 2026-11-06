"""Streaming worker and approval lifecycle."""
import threading;
import json;
import from tui.message_queue { Message, MessageQueue, QueueEmpty }
import from tui.state { LiveShell }
import from tui.core {
    _push_turn,
    _rewrite_turn,
    _finish_turn,
    _install_layout,
}
import from tui.format {
    format_tool_call,
    format_tool_result,
}
import from tui.preview { tool_result_preview }
import from agent.session { cancel_active_turn }
import from agent.session_turn { run_turn }
import from agent.modes {
    requires_approval, is_read_only_mode, read_only_mode_block_reason,
}
import from ui.screen {
      shell_resize,
}
import from ui.renderer { create_renderer }
import from tui.window { WindowSpec, WindowState }
import from tui.windows { _open_window, _close_top_window, _approval_state }

glob _active_turn_app: LiveShell | None = None;
glob _active_turn_payload: str = "";


def _collect_turn_event(kind: str, data: dict[str, any]) -> None {
    app: LiveShell | None = _active_turn_app;
    if app is None or app.evq is None {
        return;
    }
    queue: MessageQueue = app.evq;
    queue.put((str(kind), data));
}


def _approve_turn_tool(name: str, args: dict[str, any]) -> any {
    app: LiveShell | None = _active_turn_app;
    if app is None {
        return "denied by user";
    }
    cmd: str = "";
    if isinstance(args, dict) {
        cmd = str(args.get("cmd", ""));
    }
    policy: str = requires_approval(app.mode, name, cmd);
    if policy == "auto" {
        return True;
    }
    if policy == "blocked" {
        if is_read_only_mode(app.mode) {
            return read_only_mode_block_reason(name, app.mode);
        }
        return "blocked in " + app.mode + " mode";
    }
    if app.evq is None {
        return "denied by user";
    }
    queue: MessageQueue = app.evq;
    approval_data: dict[str, any] = {};
    approval_data["tool"] = name;
    approval_data["args"] = args;
    queue.put(("__approve__", approval_data));
    ev: threading.Event = threading.Event();
    app.appr_event = ev;
    app.appr_approved = False;
    approved: bool = ev.wait(600.0);
    app.appr_event = None;
    if not approved or not app.appr_approved {
        return "denied by user";
    }
    return True;
}


def _turn_worker() {
    app: LiveShell | None = _active_turn_app;
    if app is None or app.evq is None {
        _active_turn_app = None;
        return;
    }
    queue: MessageQueue = app.evq;
    payload: str = _active_turn_payload;
    try {
        answer: str = run_turn(payload, _collect_turn_event, approve=_approve_turn_tool);
        _active_turn_app = None;
        done_data: dict[str, any] = {};
        done_data["answer"] = answer;
        queue.put(("__done__", done_data));
    } except Exception as e {
        _active_turn_app = None;
        error_data: dict[str, any] = {};
        error_data["message"] = str(e);
        queue.put(("error", error_data));
        done_data: dict[str, any] = {};
        done_data["answer"] = "";
        queue.put(("__done__", done_data));
    }
}


def:pub _apply_resize(app: LiveShell, columns: int, rows: int) {
    if columns < 40 {
        columns = 40;
    }
    if rows < 12 {
        rows = 12;
    }
    if columns == app.columns and rows == app.rows {
        return;
    }
    app.columns = columns;
    app.rows = rows;
    shell_resize(app.session, app.shell, columns, rows);
    app.renderer = create_renderer(columns, rows);
    _install_layout(app);
    app.proj.viewport_width = max(12, columns - 2);
    app.proj.viewport_height = max(4, rows - 6);
    app.dirty = True;
}


"""Launch the real agent turn on a worker thread.

Events flow through app.evq as (kind, data) pairs consumed by _tick_stream;
the worker is a daemon so esc/quit never hangs on a stuck transport."""
def:pub _begin_assistant_reply(app: LiveShell, user_text: str, model_text: str = "") {
    # Transcript shows the RAW user line (mirrors the legacy shells);
    # model_text — when different — is the context-expanded payload
    # (@file blocks / !cmd output) actually sent downstream.
    payload = model_text if model_text else user_text;
    _push_turn(app, "user", user_text);
    app.phase = "streaming";
    app.stream_full = "";
    app.stream_shown = 0;
    app.stream_tick = 0;
    # Capture the queue LOCALLY: _finish_stream nulls app.evq when the turn
    # ends, and late worker events must never dereference that field.
    q = MessageQueue();
    app.evq = q;
    _active_turn_app = app;
    _active_turn_payload = payload;
    app.stream_msg_id = _push_turn(app, "assistant", "▍");
    app.worker = threading.Thread(target=_turn_worker, daemon=True);
    app.worker.start();
}


def:pub _finish_stream(app: LiveShell, final_body: str) {
    body = final_body if final_body else app.stream_full;
    if not body.strip() {
        body = "(no response)";
    }
    _finish_turn(app, app.stream_msg_id, "assistant", body.rstrip());
    app.phase = "ready";
    app.worker = None;
    app.evq = None;
    app.dirty = True;
}


def:pub _tick_stream(app: LiveShell) {
    if app.phase != "streaming" or app.evq is None {
        return;
    }
    app.spin_i += 1;
    drained = False;
    chunks_pending: bool = False;
    while True {
        try {
            item: Message = app.evq.get_nowait();
        } except QueueEmpty {
            break;
        }
        kind = str(item[0]);
        data: dict[str, any] = item[1];
        drained = True;
        if kind == "chunk" {
            app.stream_full = app.stream_full + str(data.get("content", ""));
            chunks_pending = True;
        } elif kind == "tool_call" {
            args: any = data.get("args", {});
            summary = format_tool_call(str(data.get("tool", "")), args if isinstance(args, dict) else {});
            app.tool_msg_id = _push_turn(app, "tool", summary);
            _rewrite_turn(app, app.tool_msg_id, "tool", summary);
        } elif kind == "tool_result" {
            _push_turn(
                app,
                "tool",
                format_tool_result(tool_result_preview(str(data.get("result", "")))),
            );
        } elif kind == "retry" {
            note = "retry " + str(data.get("attempt", "?")) + "/" + str(data.get("max_retries", "?"));
            _push_turn(app, "tool", "retry  " + note + "\n        " + str(data.get("message", ""))[:120]);
        } elif kind == "cancelled" {
            app.stream_full = app.stream_full + "\n[cancelled]";
        } elif kind == "loop_limit" {
            _push_turn(app, "tool", "stop  iteration limit reached");
        } elif kind == "extensions" {
            label = str(data.get("label", ""));
            if label {
                _push_turn(app, "tool", "ext  " + label);
            }
        } elif kind == "entry" {
            _push_turn(
                app,
                "tool",
                "log  "
                + str(data.get("type", "entry"))
                + "  "
                + str(data.get("content", ""))[:100],
            );
        } elif kind == "error" {
            msg = str(data.get("message", "unknown error"));
            app.stream_full = "ERROR: " + msg[:400];
            _rewrite_turn(app, app.stream_msg_id, "assistant", app.stream_full);
        } elif kind == "__approve__" {
            tool_name = str(data.get("tool", "?"));
            args: any = data.get("args", {});
            approval_args: dict[str, any] = args if isinstance(args, dict) else {};
            args_text: str = json.dumps(approval_args);
            approval_label = tool_name + "(" + args_text[:160] + ")";
            app.phase = "approval";
            _open_window(
                app,
                WindowState(
                    spec=WindowSpec(title="TOOL APPROVAL", width=46),
                    kind="approval",
                    payload={"tool": tool_name, "args": approval_args},
                ),
                force=True,
            );
            _push_turn(app, "tool", "await  approve\n        " + approval_label);
                    app.dirty = True;
        } elif kind == "__done__" {
            _finish_stream(app, str(data.get("answer", "")));
            return;
        }
    }
    if chunks_pending {
        # Rewrite the streaming turn at most ONCE per drain: _rewrite_turn
        # re-projects the whole assistant body, so a rewrite per chunk made
        # long streaming answers quadratic. This loop drains once per 40 ms
        # tick, so rewrites are bounded by tick rate, not chunk count.
        _rewrite_turn(app, app.stream_msg_id, "assistant", app.stream_full + "▍");
    }
    if drained {
        app.dirty = True;
    }
}
def:pub _accept_approval(app: LiveShell) {
    if app.phase != "approval" or _approval_state(app) is None {
        return;
    }
    _close_top_window(app);
    app.appr_approved = True;
    if app.appr_event is not None {
        app.appr_event.set();
    }
    _push_turn(app, "tool", "ok  approved");
    app.phase = "streaming";
    app.dirty = True;
}


def:pub _reject_approval(app: LiveShell) {
    if app.phase == "approval" {
        if _approval_state(app) is None {
            return;
        }
        _close_top_window(app);
        app.appr_approved = False;
        if app.appr_event is not None {
            app.appr_event.set();
        }
        _push_turn(app, "tool", "ok  denied");
        app.phase = "streaming";
        app.dirty = True;
        return;
    }
    if app.phase == "streaming" {
        cancel_active_turn();
        app.dirty = True;
        return;
    }
    app.running = False;
}
