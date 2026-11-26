impl _absorb_hook_results(bridge: PluginBridge, results: list[any]) {
    for r in results {
        if isinstance(r, dict) and r.get("ui_events") {
            _absorb_payload(bridge, {"ui_events": r["ui_events"]});
        }
    }
}

impl fire_hook_data(
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
            reply = _read_node_until(bridge, "hook_done", correlation_id=corr, timeout=timeout);
        } except Exception {
            return empty;
        }
        touch_bridge(bridge);
        raw: any = reply.payload.get("results", []);
        out_list: list[any] = raw if isinstance(raw, list) else [];
        final: any = reply.payload.get("data");
        final_data: dict[str, any] = dict(final) if isinstance(final, dict) else dict(data);
        _absorb_payload(bridge, dict(reply.payload));
        _absorb_hook_results(bridge, out_list);
        return {"results": out_list, "data": final_data};
    }
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
            if (
                isinstance(out, dict)
                and str(out.get("action")) == "transform"
                and out.get("text") is not None
            ) {
                working["text"] = str(out.get("text"));
            }
            if isinstance(out, dict) {
                if isinstance(out.get("content"), str) {
                    working["content"] = out["content"];
                }
                if isinstance(out.get("isError"), bool) {
                    working["isError"] = out["isError"];
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

impl _ok_verdicts(results: list[any]) -> list[any] {
    verdicts: list[any] = [];
    for r in results {
        if isinstance(r, dict) and r.get("ok") and isinstance(r.get("verdict"), dict) {
            verdicts.append(r["verdict"]);
        }
    }
    return verdicts;
}

impl tool_call_gate(
    bridge: PluginBridge | None, name: str, args: dict[str, any]
) -> dict[str, any] {
    out: dict[str, any] = {"blocked": False, "reason": "", "terminate": False, "args": args};
    if bridge is None {
        return out;
    }
    data = {"toolName": str(name), "toolCallId": "", "input": args};
    try {
        fired = fire_hook_data(bridge, "tool_call", data);
        results = fired["results"];
        final = fired["data"];
    } except Exception {
        return out;
    }
    mutated: any = final.get("input") if isinstance(final, dict) else None;
    if isinstance(mutated, dict) {
        out["args"] = mutated;
    }
    for v in _ok_verdicts(results) {
        if v.get("block") {
            out["blocked"] = True;
            out["reason"] = str(v.get("reason", ""));
            out["terminate"] = bool(v.get("terminate", False));
            break;
        }
    }
    return out;
}

impl tool_result_gate(
    bridge: PluginBridge | None, name: str, args: dict[str, any], result: str
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
        results = fired.get("results", []);
        final = fired.get("data", {});
    } except Exception {
        return out;
    }
    any_ok = False;
    for v in _ok_verdicts(results) {
        if isinstance(v.get("content"), str) or isinstance(v.get("isError"), bool) {
            any_ok = True;
        }
    }
    if not any_ok {
        return out;
    }
    content: any = final.get("content") if isinstance(final, dict) else None;
    is_err: any = final.get("isError") if isinstance(final, dict) else None;
    out["ok"] = True;
    if isinstance(content, str) {
        out["result"] = content;
    }
    out["is_error"] = bool(is_err) if isinstance(is_err, bool) else False;
    return out;
}

impl input_gate(bridge: PluginBridge | None, text: str) -> dict[str, any] {
    out: dict[str, any] = {"action": "continue", "text": str(text)};
    if bridge is None {
        return out;
    }
    try {
        fired = fire_hook_data(bridge, "input", {"text": str(text), "source": "interactive"});
        results = fired.get("results", []);
        final = fired.get("data", {});
    } except Exception {
        return out;
    }
    for v in _ok_verdicts(results) {
        if str(v.get("action", "continue")) == "handled" {
            t: any = final.get("text") if isinstance(final, dict) else None;
            return {"action": "handled", "text": str(t) if isinstance(t, str) else out["text"]};
        }
        if str(v.get("action", "continue")) == "transform" {
            out["action"] = "transform";
        }
    }
    if out["action"] == "transform" and isinstance(final, dict) {
        t2: any = final.get("text");
        if isinstance(t2, str) {
            out["text"] = t2;
        }
    }
    return out;
}

impl context_gate(
    bridge: PluginBridge | None, messages: list[dict[str, any]]
) -> list[dict[str, any]] {
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
        results = fired["results"];
        final = fired["data"];
    } except Exception {
        return messages;
    }
    replaced: any = None;
    for v in _ok_verdicts(results) {
        if isinstance(v.get("messages"), list) {
            replaced = v["messages"];
        }
    }
    if replaced is not None {
        return replaced;
    }
    echoed: any = final.get("messages") if isinstance(final, dict) else None;
    if isinstance(echoed, list) {
        return echoed;
    }
    return messages;
}

impl agent_start_gate(bridge: PluginBridge | None, prompt: str) -> dict[str, any] {
    out: dict[str, any] = {"message": "", "systemPrompt": ""};
    if bridge is None {
        return out;
    }
    try {
        fired = fire_hook_data(bridge, "before_agent_start", {"prompt": str(prompt)});
        results = fired["results"];
    } except Exception {
        return out;
    }
    for v in _ok_verdicts(results) {
        sp = v.get("systemPrompt");
        if isinstance(sp, str) and sp {
            out["systemPrompt"] = sp;
        }
        m: any = v.get("message");
        if isinstance(m, dict) and m.get("content") is not None {
            out["message"] = str(m.get("content"));
        } elif isinstance(m, str) and m {
            out["message"] = m;
        }
    }
    return out;
}

impl fire_hook(
    bridge: PluginBridge, event: str, data: dict[str, any], timeout: float = 10.0
) -> list[dict[str, any]] {
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
            reply = _read_node_until(bridge, "hook_done", correlation_id=corr, timeout=timeout);
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

impl fire_user_bash(
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

impl fire_project_trust(bridge: PluginBridge | None, path: str) -> list[dict[str, any]] {
    if bridge is None {
        return [];
    }
    try {
        return fire_hook(bridge, "project_trust", {"path": str(path)});
    } except Exception {
        return [];
    }
}
