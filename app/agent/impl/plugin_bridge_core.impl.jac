impl PluginBridge.invoke_js_tool(name: str, args: dict[str, any]) -> str {
    return invoke_tool(self, name, args);
}

impl create_bridge(session_id: str) -> PluginBridge {
    return PluginBridge(session_id=session_id);
}

impl _alloc_corr(bridge: PluginBridge) -> str {
    corr = "corr-" + str(bridge.next_corr);
    bridge.next_corr += 1;
    return corr;
}

impl _node_alive(bridge: PluginBridge) -> bool {
    if bridge.host_kind != "node" or bridge.proc is None {
        return False;
    }
    return bridge.proc.poll() is None;
}

impl _emit_host_status(bridge: PluginBridge, phase: str, detail: str = "") {
    bridge.status_phase = phase;
    bridge.inbox.append(
        make_envelope(
            kind="host_status",
            session_id=bridge.session_id,
            payload={"phase": phase, "detail": detail},
        ),
    );
}

impl invoke_tool(bridge: PluginBridge, name: str, args: dict[str, any]) -> str {
    if bridge.host_kind == "node" and not _node_alive(bridge) {
        host_status(bridge);
        return "ERROR: plugin host unavailable";
    }
    if bridge.host_kind == "node" {
        result = _invoke_tool_node(bridge, name, args);
    } else {
        result = _invoke_tool_fake(bridge, name, args);
    }
    if not str(result).startswith("ERROR: plugin host unavailable") {
        touch_bridge(bridge);
    } elif bridge.host_kind == "node" {
        host_status(bridge);
    }
    return result;
}

impl _invoke_tool_fake(bridge: PluginBridge, name: str, args: dict[str, any]) -> str {
    ensure_host(bridge);
    h = bridge.host;
    if h is None or not h.alive {
        return "ERROR: plugin host unavailable";
    }
    corr = _alloc_corr(bridge);
    if corr in h.cancelled {
        result_env = make_envelope(
            kind="tool_result",
            session_id=bridge.session_id,
            tool_id=name,
            correlation_id=corr,
            payload={"ok": False, "error": "cancelled"},
        );
        bridge.inbox.append(result_env);
        return "ERROR: cancelled";
    }
    if name not in h.handlers {
        bridge.inbox.append(
            make_envelope(
                kind="tool_result",
                session_id=bridge.session_id,
                tool_id=name,
                correlation_id=corr,
                payload={"ok": False, "error": f"unknown tool {name}"},
            ),
        );
        return f"ERROR: unknown js tool {name}";
    }
    if h.active_tools is not None and name not in h.active_tools {
        bridge.inbox.append(
            make_envelope(
                kind="tool_result",
                session_id=bridge.session_id,
                tool_id=name,
                correlation_id=corr,
                payload={"ok": False, "error": f"tool {name} is not active"},
            ),
        );
        return f"ERROR: tool {name} is not active";
    }
    try {
        result = str(h.handlers[name](**args));
        ok = True;
        err = "";
    } except Exception as e {
        result = "";
        ok = False;
        err = str(e);
    }
    payload: dict[str, any] = {"ok": ok};
    if ok {
        payload["result"] = result;
    } else {
        payload["error"] = err or "invoke failed";
    }
    bridge.inbox.append(
        make_envelope(
            kind="tool_result",
            session_id=bridge.session_id,
            tool_id=name,
            correlation_id=corr,
            payload=payload,
        ),
    );
    if ok {
        return result;
    }
    return f"ERROR: {payload['error']}";
}

impl _invoke_tool_node(bridge: PluginBridge, name: str, args: dict[str, any]) -> str {
    if not _node_alive(bridge) {
        phase = maybe_restart_host(bridge);
        if phase != "ready" or not _node_alive(bridge) {
            return "ERROR: plugin host unavailable";
        }
    }
    corr = _alloc_corr(bridge);
    _prepare_corr(bridge, corr, expect_kind="tool_result");
    req = make_envelope(
        kind="tool_invoke",
        session_id=bridge.session_id,
        tool_id=name,
        correlation_id=corr,
        payload={"name": name, "args": args},
    );
    try {
        _write_node(bridge, req);
        reply = _read_node_until(bridge, "tool_result", correlation_id=corr, timeout=10.0);
    } except Exception as e {
        return f"ERROR: {e}";
    }
    ok = bool(reply.payload.get("ok", False));
    _absorb_payload(bridge, dict(reply.payload));
    if ok {
        return str(reply.payload.get("result", ""));
    }
    return f"ERROR: {reply.payload.get('error', 'invoke failed')}";
}
