impl transform_markdown(
    bridge: PluginBridge | None,
    markdown: str,
    message_type: str = "assistant",
    streaming: bool = False,
) -> dict[str, any] {
    md = str(markdown);
    if bridge is None {
        return {"ok": True, "markdown": md};
    }
    mctx: dict[str, any] = {"message_type": message_type, "isStreaming": streaming};
    if bridge.host_kind == "node" and _node_alive(bridge) {
        corr = _alloc_corr(bridge);
        _prepare_corr(bridge, corr, expect_kind="md_transformed");
        req = make_envelope(
            kind="md_transform",
            session_id=bridge.session_id,
            correlation_id=corr,
            payload={"markdown": md, "message_type": message_type, "streaming": streaming},
        );
        try {
            _write_node(bridge, req);
            reply = _read_node_until(bridge, "md_transformed", correlation_id=corr, timeout=10.0);
        } except Exception as e {
            return {"ok": False, "error": str(e), "markdown": md};
        }
        touch_bridge(bridge);
        out = dict(reply.payload);
        out["ok"] = True;
        _absorb_payload(bridge, out);
        return out;
    }
    h = bridge.host;
    if h is None or not h.alive {
        return {"ok": True, "markdown": md};
    }
    for t in h.md_transformers {
        try {
            xformed: any = t["fn"](md, mctx);
            if isinstance(xformed, str) {
                md = xformed;
            }
        } except Exception {}
    }
    return {"ok": True, "markdown": md};
}

impl drain_extension_traffic(bridge: PluginBridge | None) -> dict[str, any] {
    if bridge is None {
        return {"messages": [], "entries": []};
    }
    h = bridge.host;
    if h is not None {
        _absorb_pending_fake(bridge, h);
        if h.session_name {
            _absorb_payload(bridge, {"session_name": h.session_name});
        }
    }
    out: dict[str, any] = {
        "messages": list(bridge.traffic_messages),
        "entries": list(bridge.traffic_entries),
    };
    bridge.traffic_messages.clear();
    bridge.traffic_entries.clear();
    return out;
}

impl set_session_name(bridge: PluginBridge, name: str, timeout: float = 5.0) -> bool {
    bridge.session_name = str(name);
    if bridge.host_kind == "node" and _node_alive(bridge) {
        corr = _alloc_corr(bridge);
        _prepare_corr(bridge, corr, expect_kind="rendered");
        req = make_envelope(
            kind="hook_fire",
            session_id=bridge.session_id,
            correlation_id=corr,
            payload={"event": "__session_name", "data": {}, "session_name": str(name)},
        );
        try {
            _write_node(bridge, req);
            _read_node_until(bridge, "hook_done", correlation_id=corr, timeout=timeout);
        } except Exception as e {
            return False;
        }
    }
    h = bridge.host;
    if h is not None {
        h.session_name = str(name);
    }
    return True;
}

impl resolve_ext_model(bridge: PluginBridge | None, model_id: str) -> dict[str, any] | None {
    parts = str(model_id).split("/");
    if len(parts) != 3 or parts[0] != "ext" or not parts[1] or not parts[2] {
        return None;
    }
    if bridge is None {
        return None;
    }
    ext_id = parts[1];
    model = parts[2];
    for name in bridge.providers {
        cfg = bridge.providers[name];
        if str(cfg.get("extension_id", "")) != ext_id {
            continue;
        }
        for m in cfg.get("models", []) or [] {
            mid = m.get("id", "") if isinstance(m, dict) else str(m);
            if str(mid) == model {
                return {
                    "provider": str(name),
                    "model": model,
                    "base_url": str(cfg.get("base_url", "") or ""),
                    "streaming": cfg.get("streaming", True) is not False,
                    "extension_id": ext_id,
                };
            }
        }
    }
    return None;
}

impl prepare_provider_request(
    bridge: PluginBridge | None, model: str, url: str, headers: dict[str, str], body: dict[str, any]
) -> dict[str, any] {
    out: dict[str, any] = {"url": url, "headers": headers, "body": body};
    if bridge is None {
        return out;
    }
    data = {"model": str(model), "url": url, "headers": headers, "body": body};
    try {
        fired = fire_hook_data(bridge, "before_provider_request", data);
    } except Exception {
        return out;
    }
    final = fired.get("data", {}) if isinstance(fired, dict) else {};
    results = fired.get("results", []) if isinstance(fired, dict) else [];
    for key in ("url", "headers", "body") {
        v: any = final.get(key) if isinstance(final, dict) else None;
        if v is not None {
            out[key] = v;
        }
    }
    for verdict in _ok_verdicts(results) {
        v: any = verdict;
        u = v.get("url");
        if isinstance(u, str) and u {
            out["url"] = u;
        }
        for key in ("headers", "body") {
            if isinstance(v.get(key), dict) {
                out[key] = v[key];
            }
        }
    }
    return out;
}

impl _fake_content_lines(out: any) -> list[str] {
    if out is None {
        return [];
    }
    if isinstance(out, list) {
        return [str(x) for x in out];
    }
    if isinstance(out, dict) and isinstance(out.get("lines"), list) {
        return [str(x) for x in out["lines"]];
    }
    return [x for x in str(out).split("\n")];
}

impl render_extension_block(
    bridge: PluginBridge | None, kind: str, entry_type: str, payload: any
) -> dict[str, any] {
    none_out: dict[str, any] = {"ok": False, "lines": []};
    if bridge is None {
        return none_out;
    }
    if bridge.host_kind == "node" and _node_alive(bridge) {
        corr = _alloc_corr(bridge);
        _prepare_corr(bridge, corr, expect_kind="rendered");
        req = make_envelope(
            kind="render_message",
            session_id=bridge.session_id,
            correlation_id=corr,
            payload={"kind": kind, "type": entry_type, "payload": payload},
        );
        try {
            _write_node(bridge, req);
            reply = _read_node_until(bridge, "rendered", correlation_id=corr, timeout=10.0);
        } except Exception {
            return none_out;
        }
        touch_bridge(bridge);
        ok = bool(reply.payload.get("ok", False));
        raw: any = reply.payload.get("lines", []);
        lines: list[str] = [str(x) for x in raw] if isinstance(raw, list) else [];
        return {"ok": ok, "lines": lines};
    }
    h = bridge.host;
    if h is None or not h.alive {
        return none_out;
    }
    table = h.message_renderers if kind != "entry" else h.entry_renderers;
    renderer: any = table.get(str(entry_type));
    if renderer is None or not isinstance(renderer, dict) {
        return none_out;
    }
    try {
        out: any = renderer["fn"](payload);
        return {"ok": True, "lines": _fake_content_lines(out)};
    } except Exception as e {
        text = "" if payload is None else str(payload);
        return {"ok": False, "error": str(e), "lines": [x for x in text.split("\n")]};
    }
}
