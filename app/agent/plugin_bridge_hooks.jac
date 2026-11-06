"""Plugin bridge lifecycle hooks and verdict gates."""

import json;

import from .protocol { Envelope, make_envelope }
import from .fake_host { FakePluginHost, FakeUi, touch_bridge }
import from .plugin_bridge_core {
    PluginBridge,
    _alloc_corr,
    _node_alive,
}
import from .plugin_bridge_io { _write_node, _prepare_corr, _read_node_until }
import from .plugin_bridge_traffic {
    _absorb_payload,
    _absorb_pending_fake,
}

def:pub _absorb_hook_results(bridge: PluginBridge, results: list[dict[str, any]]) {
    b: PluginBridge = bridge as PluginBridge;
    for r in results {
        if isinstance(r, dict) and r.get("ui_events") {
            _absorb_payload(b, {"ui_events": r["ui_events"]});
        }
    }
}

# ===================== batch-2 events + structured verdicts =====================

"""Fire a hook and return (results, final_data).

For `tool_call` / `context` the host hands handlers a deep copy they mutate
IN PLACE (later handlers see earlier mutations — Pi semantics) and echoes the
final working copy back as hook_done payload `data`. Other events return
`data` unchanged. Results entries carry `verdict`: the handler's raw object
return ({block}, {action}, {messages}, ...) or None for scalar/None returns.
Returns {results, data}; never raises on transport failure (empty results)."""
def:pub fire_hook_data(
    bridge: PluginBridge | None, event: str, data: dict[str, any], timeout: float = 10.0
) -> dict[str, any] {
    empty: dict[str, any] = {"results": [], "data": dict(data)};
    if bridge is None {
        return empty;
    }
    if bridge.host_kind == "node" and _node_alive(bridge) {
        corr = _alloc_corr(bridge);
        _prepare_corr(bridge, corr, expect_kind="hook_done");
        req = make_envelope(
            kind="hook_fire",
            session_id=bridge.session_id,
            correlation_id=corr,
            payload={"event": event, "data": data},
        );
        try {
            _write_node(bridge, req);
            reply = _read_node_until(
                bridge, "hook_done", correlation_id=corr, timeout=timeout
            );
        } except Exception {
            return empty;
        }
        touch_bridge(bridge);
        raw: any = reply.payload.get("results", []);
        out_list: list[dict[str, any]] = raw as list[dict[str, any]] if isinstance(raw, list) else [];
        final: any = reply.payload.get("data");
        final_data: dict[str, any] = dict(final) if isinstance(final, dict) else dict(data);
        _absorb_payload(bridge, dict(reply.payload));
        _absorb_hook_results(bridge, out_list);
        return {"results": out_list, "data": final_data};
    }
    # Fake host path: handlers receive the live dict; Python mutations are
    # visible to later handlers directly (in-place chaining for free).
    h = bridge.host;
    if h is None or not h.alive {
        return empty;
    }
    working = dict(data);
    results: list[dict[str, any]] = [];
    for handler in h.listeners.get(event, []) {
        notifications: list[str] = [];
        try {
            ui = FakeUi(notifications, []);
            out = handler(working, {"ui": ui});
            out_map: dict[str, any] = {};
            if isinstance(out, dict) {
                out_map = out as dict[str, any];
            }
            # Transform verdicts rewrite the working text so later handlers
            # see the composed input (Pi input-transform chaining).
            if (
                "action" in out_map
                and str(out_map["action"]) == "transform"
                and "text" in out_map
                and out_map["text"] is not None
            ) {
                working["text"] = str(out_map["text"]);
            }
            # tool_result middleware: partial patches apply to the working
            # copy so later handlers see the latest result.
            if isinstance(out, dict) {
                if "content" in out_map and isinstance(out_map["content"], str) {
                    working["content"] = out_map["content"];
                }
                if "isError" in out_map and isinstance(out_map["isError"], bool) {
                    working["isError"] = out_map["isError"];
                }
            }
            entry_r: dict[str, any] = {
                "ok": True,
                "result": "" if out is None else str(out),
                "verdict": out if isinstance(out, dict) else None,
                "notifications": notifications,
            };
            if ui.ui_events {
                entry_r["ui_events"] = list(ui.ui_events);
            }
            results.append(entry_r);
        } except Exception as e {
            results.append({
                "ok": False,
                "error": str(e),
                "verdict": None,
                "notifications": notifications,
            });
        }
    }
    _absorb_pending_fake(bridge, h);
    _absorb_hook_results(bridge, results);
    return {"results": results, "data": working};
}


"""Verdict dicts from successful listener results, in fire order."""
def:pub _ok_verdicts(results: list[dict[str, any]]) -> list[dict[str, any]] {
    verdicts: list[dict[str, any]] = [];
    for r in results {
        if "ok" in r and bool(r["ok"]) and "verdict" in r and isinstance(r["verdict"], dict) {
            verdicts.append(r["verdict"] as dict[str, any]);
        }
    }
    return verdicts;
}


"""tool_call gate: fires the Pi `tool_call` hook and aggregates verdicts.

Returns {blocked, reason, terminate, args} where args is the (possibly
handler-mutated) tool input to actually execute with. First blocking handler
wins. Never raises — default verdict lets the call through."""
def:pub tool_call_gate(bridge: PluginBridge | None, name: str, args: dict[str, any]) -> dict[str, any] {
    out: dict[str, any] = {"blocked": False, "reason": "", "terminate": False, "args": args};
    if bridge is None {
        return out;
    }
    data = {"toolName": str(name), "toolCallId": "", "input": args};
    try {
        fired = fire_hook_data(bridge, "tool_call", data);
        results: list[dict[str, any]] = fired["results"] as list[dict[str, any]];
        final: dict[str, any] = fired["data"] as dict[str, any];
    } except Exception {
        return out;
    }
    mutated: any = final["input"] if "input" in final else None;
    if isinstance(mutated, dict) {
        out["args"] = mutated;
    }
    for v in _ok_verdicts(results) {
        if "block" in v and bool(v["block"]) {
            out["blocked"] = True;
            out["reason"] = str(v["reason"]) if "reason" in v else "";
            out["terminate"] = bool(v["terminate"]) if "terminate" in v else False;
            break;
        }
    }
    return out;
}


"""tool_result gate: fires the Pi `tool_result` hook over a finished result.

Pi middleware semantics: each handler sees the latest content (hosts apply
{content, isError} patches between handlers) and may return partial patches.
Returns {ok, result, is_error} — never raises; on any failure the original
result passes through untouched."""
def:pub tool_result_gate(
    bridge: PluginBridge | None,
    name: str,
    args: dict[str, any],
    result: str,
) -> dict[str, any] {
    out: dict[str, any] = {"ok": True, "result": result, "is_error": False};
    if bridge is None {
        return out;
    }
    data = {
        "toolName": str(name),
        "toolCallId": "",
        "input": args,
        "content": result,
        "isError": False,
    };
    try {
        fired = fire_hook_data(bridge, "tool_result", data);
        results: list[dict[str, any]] = fired["results"] as list[dict[str, any]];
        final: dict[str, any] = fired["data"] as dict[str, any];
    } except Exception {
        return out;
    }
    any_ok = False;
    for v in _ok_verdicts(results) {
        if ("content" in v and isinstance(v["content"], str)) or ("isError" in v and isinstance(v["isError"], bool)) {
            any_ok = True;
        }
    }
    if not any_ok {
        return out;
    }
    content: any = final["content"] if "content" in final else None;
    is_err: any = final["isError"] if "isError" in final else None;
    out["ok"] = True;
    if isinstance(content, str) {
        out["result"] = content;
    }
    out["is_error"] = bool(is_err) if isinstance(is_err, bool) else False;
    return out;
}


"""input gate: fires the Pi `input` hook over raw user text.

Returns {action, text} — action is continue | transform | handled (first
handled wins). Transforms CHAIN: hosts apply each transform verdict to the
working copy between handlers, so later handlers and the echoed final text
see the composed result — the echoed text is authoritative."""
def:pub input_gate(bridge: PluginBridge | None, text: str) -> dict[str, any] {
    out: dict[str, any] = {"action": "continue", "text": str(text)};
    if bridge is None {
        return out;
    }
    try {
        fired = fire_hook_data(
            bridge, "input", {"text": str(text), "source": "interactive"}
        );
        results: list[dict[str, any]] = fired["results"] as list[dict[str, any]];
        final: dict[str, any] = fired["data"] as dict[str, any];
    } except Exception {
        return out;
    }
    for v in _ok_verdicts(results) {
        action = str(v["action"]) if "action" in v else "continue";
        if action == "handled" {
            t: any = final["text"] if "text" in final else None;
            return {
                "action": "handled",
                "text": str(t) if isinstance(t, str) else out["text"],
            };
        }
        if action == "transform" {
            out["action"] = "transform";
        }
    }
    if out["action"] == "transform" and isinstance(final, dict) {
        t2: any = final["text"] if "text" in final else None;
        if isinstance(t2, str) {
            out["text"] = t2;
        }
    }
    return out;
}


"""context gate: fires the Pi `context` hook before each LLM call.

Handlers may edit the message copy in place (echoed back) or return
{messages} (explicit replacement — last one wins). Returns the message list
to stream with; the caller's history is never mutated."""
def:pub context_gate(bridge: PluginBridge | None, messages: list[dict[str, any]]) -> list[dict[str, any]] {
    if bridge is None {
        return messages;
    }
    try {
        snapshot: any = json.loads(json.dumps(messages));
    } except Exception {
        return messages;
    }
    if not isinstance(snapshot, list) {
        return messages;
    }
    try {
        fired = fire_hook_data(bridge, "context", {"messages": snapshot});
        results: list[dict[str, any]] = fired["results"] as list[dict[str, any]];
        final: dict[str, any] = fired["data"] as dict[str, any];
    } except Exception {
        return messages;
    }
    replaced: any = None;
    for v in _ok_verdicts(results) {
        if "messages" in v and isinstance(v["messages"], list) {
            replaced = v["messages"];
        }
    }
    if replaced is not None {
        return replaced;
    }
    echoed: any = final["messages"] if "messages" in final else None;
    if isinstance(echoed, list) {
        return echoed;
    }
    return messages;
}


"""before_agent_start gate: aggregate {message, systemPrompt} returns.

systemPrompt composes last-wins across handlers (each handler built its
string from the same base prompt in this single-round-trip design — full
chaining would need per-handler round trips). Message injection keeps the
last non-empty content."""
def:pub agent_start_gate(bridge: PluginBridge | None, prompt: str) -> dict[str, any] {
    out: dict[str, any] = {"message": "", "systemPrompt": ""};
    if bridge is None {
        return out;
    }
    try {
        fired = fire_hook_data(
            bridge, "before_agent_start", {"prompt": str(prompt)}
        );
        results: list[dict[str, any]] = fired["results"] as list[dict[str, any]];
    } except Exception {
        return out;
    }
    for v in _ok_verdicts(results) {
        sp = v["systemPrompt"] if "systemPrompt" in v else None;
        if isinstance(sp, str) and sp {
            out["systemPrompt"] = sp;
        }
        m: any = v["message"] if "message" in v else None;
        if isinstance(m, dict) and "content" in m and m["content"] is not None {
            out["message"] = str(m["content"]);
        } elif isinstance(m, str) and m {
            out["message"] = m;
        }
    }
    return out;
}

def:pub fire_hook(bridge: PluginBridge, event: str, data: dict[str, any], timeout: float = 10.0) -> list[dict[str, any]] {
    if bridge.host_kind == "node" and _node_alive(bridge) {
        corr = _alloc_corr(bridge);
        _prepare_corr(bridge, corr, expect_kind="hook_done");
        req = make_envelope(
            kind="hook_fire",
            session_id=bridge.session_id,
            correlation_id=corr,
            payload={"event": event, "data": data},
        );
        try {
            _write_node(bridge, req);
            reply = _read_node_until(
                bridge, "hook_done", correlation_id=corr, timeout=timeout
            );
        } except Exception {
            return [];
        }
        touch_bridge(bridge);
        raw: any = reply.payload.get("results", []);
        out_list: list[any] = raw if isinstance(raw, list) else [];
        _absorb_payload(bridge, dict(reply.payload));
        _absorb_hook_results(bridge, out_list);
        return out_list;
    }
    # Fake host path.
    h = bridge.host;
    if h is None or not h.alive {
        return [];
    }
    results: list[dict[str, any]] = [];
    for handler in h.listeners.get(event, []) {
        notifications: list[str] = [];
        try {
            ui = FakeUi(notifications, []);
            out = handler(data, {"ui": ui});
            entry_r: dict[str, any] = {
                "ok": True,
                "result": "" if out is None else str(out),
                "verdict": out if isinstance(out, dict) else None,
                "notifications": notifications,
            };
            if ui.ui_events {
                entry_r["ui_events"] = list(ui.ui_events);
            }
            results.append(entry_r);
        } except Exception as e {
            results.append({
                "ok": False,
                "error": str(e),
                "verdict": None,
                "notifications": notifications,
            });
        }
    }
    _absorb_pending_fake(bridge, h);
    _absorb_hook_results(bridge, results);
    return results;
}


"""Native-safe informational provider response hook boundary.

The HTTP transport passes its header map as JSON across the module boundary;
the bridge module reconstructs the dynamic hook payload beside fire_hook.
"""
def:pub notify_after_provider_response(
    bridge: PluginBridge, status: int, headers_json: str, timeout: float,
) -> None {
    if bridge is None {
        return;
    }
    headers: dict[str, str] = json.loads(headers_json) as dict[str, str];
    data: dict[str, any] = {"status": status, "headers": headers};
    fire_hook(bridge as PluginBridge, "after_provider_response", data, timeout=timeout);
}


# ===================== cheap lifecycle events (name-pinned helpers) =====================

"""Fire the Pi `user_bash` hook when the agent runs a shell command.

Payload mirrors Pi: {command, result?}. Session-side call site (one-liner
when wired): relay_tool_hooks in agent/session.jac — fire where tool ==
"run_command". Best-effort: no host or transport failure returns []."""
def:pub fire_user_bash(
    bridge: PluginBridge | None, command: str, result: str = ""
) -> list[dict[str, any]] {
    if bridge is None {
        return [];
    }
    data: dict[str, any] = {"command": str(command)};
    if result {
        data["result"] = str(result)[:2000];
    }
    try {
        return fire_hook(bridge, "user_bash", data);
    } except Exception {
        return [];
    }
}


"""Fire the Pi `project_trust` hook when a project directory is first
trusted. Payload: {path}. Best-effort: no host or transport failure
returns []."""
def:pub fire_project_trust(bridge: PluginBridge | None, path: str) -> list[dict[str, any]] {
    if bridge is None {
        return [];
    }
    try {
        return fire_hook(bridge, "project_trust", {"path": str(path)});
    } except Exception {
        return [];
    }
}


# ======================= T2-partial: markdown transformers =======================
