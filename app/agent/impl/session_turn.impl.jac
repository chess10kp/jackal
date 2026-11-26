impl render_event(kind: str, data: dict[str, any]) {
    out: any = sys.stdout;
    if kind == "chunk" {
        out.write(str(data.get("content", "")));
        out.flush();
    } elif kind == "tool_call" {
        out.write("\n");
        args: any = data.get("args", {});
        parts: list[str] = [];
        for pair in args.items() {
            parts.append(str(pair[0]) + "=" + str(pair[1])[:40]);
        }
        out.write(f"  * {data.get('tool')}({(', '.join(parts))[:120]})\n");
        out.flush();
        bump_tool_count();
    } elif kind == "tool_result" {
        preview = str(data.get("result", ""))[:80].replace("\n", " ");
        out.write(f"    -> {preview}\n");
        out.flush();
    } elif kind == "error" {
        out.write(f"\n[error] {data.get('message')}\n");
        out.flush();
    } elif kind == "extensions" {
        out.write(f"\n[{data.get('label', '')}]\n");
        out.flush();
    }
}

impl relay_tool_hooks(bridge: PluginBridge | None, inner: any) -> any {
    if bridge is None {
        return inner;
    }
    def relayed(kind: str, data: dict[str, any]) {
        if kind == "tool_call" {
            fire_hook(
                bridge,
                "tool_execution_start",
                {"tool": str(data.get("tool", "")), "args": data.get("args", {})},
            );
        } elif kind == "tool_result" {
            fire_hook(
                bridge,
                "tool_execution_end",
                {"tool": str(data.get("tool", "")), "result": str(data.get("result", ""))[:2000]},
            );
        }
        inner(kind, data);
    }
    return relayed;
}

impl _apply_extension_traffic(bridge: PluginBridge | None, on_event: any) {
    if bridge is None or on_event is None {
        return;
    }
    try {
        traffic: dict[str, any] = drain_extension_traffic(bridge);
        msgs: list[dict[str, any]] = traffic["messages"];
        for m in msgs {
            history.append({
                "role": str(m.get("role", "user")),
                "content": str(m.get("content", "")),
            });
        }
        raw_entries: list[dict[str, any]] = traffic["entries"];
        for e in raw_entries {
            ent: dict[str, any] = dict(e);
            try {
                r: dict[str, any] = render_extension_block(
                    bridge as PluginBridge, "entry", str(ent.get("type", "")), ent.get("data")
                );
                if r.get("ok") and r.get("lines") {
                    ent["lines"] = r["lines"];
                }
            } except Exception {}
            on_event("entry", ent);
        }
    } except Exception {}
}

impl compaction_cut(msgs: list[dict[str, any]], keep_tail: int, floor: int = 0) -> int {
    cut: int = max(floor, len(msgs) - keep_tail);
    while cut > floor and str(msgs[cut].get("role", "")) == "tool" {
        cut -= 1;
    }
    return cut;
}

impl compact_history(bridge: PluginBridge | None = None, force: bool = False) -> dict[str, any] {
    cwd = plugins.cwd or os.getcwd();
    raw_cfg = load_project_config(cwd);
    cfg = resolve_auto_compact_config(raw_cfg, str(raw_cfg.get("compactStrategy", "")));
    if not force {
        ctx_override: any = None;
        env_max: str = os.environ.get("JACKAL_CONTEXT_MAX", "");
        if env_max.isdigit() {
            ctx_override = int(env_max);
        }
        usage = compute_context_usage(history, ctx_override);
        if not should_auto_compact(usage, cfg) {
            return {"ok": False, "reason": "below threshold"};
        }
    }
    kt: int = int(cfg.get("keepTail", 12));
    if force {
        kt = min(kt, 4);
    }
    floor: int = 1 if history and str(history[0].get("role", "")) == "system" else 0;
    cut: int = compaction_cut(history, kt, floor);
    if cut <= floor {
        return {"ok": False, "reason": "nothing to compact"};
    }
    if bridge is not None {
        results = fire_hook(
            bridge as PluginBridge,
            "session_before_compact",
            {"messages_count": len(history), "manual": force},
        );
        for r in results {
            v: any = r.get("verdict") if isinstance(r, dict) else None;
            if isinstance(v, dict) and v.get("block") {
                return {"ok": False, "reason": "blocked by extension"};
            }
        }
    }
    count_before = len(history);
    dropped = history[floor:cut];
    summary_text = build_mechanical_summary(dropped);
    strategy = "mechanical";
    if str(cfg.get("strategy", "mechanical")) == "llm" {
        llm_text = summarize_for_compaction(dropped, get_model_state(), get_thinking_level_state());
        if llm_text is not None {
            summary_text = llm_text;
            strategy = "llm";
        }
    }
    compacted: list[dict[str, any]] = [];
    if floor == 1 {
        compacted.append(history[0]);
    }
    compacted.append({"role": "user", "content": summary_text});
    for m in history[cut:] {
        compacted.append(m);
    }
    history.clear();
    for m in compacted {
        history.append(m);
    }
    if bridge is not None {
        fire_hook(
            bridge as PluginBridge,
            "session_after_compact",
            {"before": count_before, "after": len(history), "strategy": strategy},
        );
    }
    return {"ok": True, "before": count_before, "after": len(history), "strategy": strategy};
}

impl _maybe_auto_compact(bridge: PluginBridge | None) {
    try {
        compact_history(bridge, False);
    } except Exception {}
}

impl compact_now -> str {
    try {
        res = compact_history(plugins.bridge, True);
    } except Exception as e {
        return "ERROR: compaction failed: " + str(e);
    }
    if not res.get("ok") {
        return "nothing compacted (" + str(res.get("reason", "")) + ")";
    }
    return (
        "compacted "
        + str(res["before"])
        + " -> "
        + str(res["after"])
        + " messages ("
        + str(res["strategy"])
        + ")"
    );
}

impl _ensure_mode_system_prompt {
    desired: str = system_prompt_for_mode(SYSTEM_PROMPT, get_mode_state());
    if not history {
        history.append({"role": "system", "content": desired});
        return;
    }
    for i in range(len(history)) {
        if str(history[i].get("role", "")) != "system" {
            continue;
        }
        current: str = str(history[i].get("content", ""));
        if (
            current == SYSTEM_PROMPT
            or "## Plan mode (active)" in current
            or "## Ask mode (active)" in current
        ) {
            history[i]["content"] = desired;
        }
        return;
    }
}

impl run_turn(
    message: str, on_event: any = render_event, approve: any = None, max_iters: int = 30
) -> str {
    if plugins.reg is None {
        session_boot(plugins.session_id, plugins.cwd or os.getcwd(), []);
    }
    st = wait_extensions_ready();
    wait_mcp_ready();
    _apply_pending_model_requests();
    if on_event is not None and st.total > 0 {
        on_event(
            "extensions",
            {
                "label": st.label,
                "phase": st.phase,
                "loaded": st.loaded,
                "total": st.total,
                "detail": st.detail,
                "t_interactive_s": st.t_interactive_s,
                "t_ext_ready_s": st.t_ext_ready_s,
                "compat_tier": st.compat_tier,
            },
        );
    }
    bridge = plugins.bridge;
    if bridge is not None {
        try {
            igate = input_gate(bridge as PluginBridge, message);
        } except Exception {
            igate = {"action": "continue", "text": message};
        }
        if igate.get("action") == "handled" {
            _apply_extension_traffic(bridge as PluginBridge, on_event);
            return "";
        }
        if igate.get("action") == "transform" {
            message = str(igate.get("text", message));
        }
    }
    _ensure_mode_system_prompt();
    history.append({"role": "user", "content": message});
    _maybe_auto_compact(bridge);
    transport: any = None;
    if get_model_state().startswith("ext/") {
        try {
            transport = make_ext_transport(
                bridge as PluginBridge, get_model_state(), thinking=get_thinking_level_state()
            );
        } except Exception {
            transport = None;
        }
        if transport is None {
            if on_event is not None {
                on_event("error", {"message": f"unknown extension model {get_model_state()}"});
            }
            return "";
        }
    }
    if transport is None {
        transport = make_transport(
            get_model_state(), get_thinking_level_state(), hook_bridge=bridge
        );
    }
    reset_turn_stats(time.time());
    injected_system = "";
    sys_idx = -1;
    saved_sys = "";
    if bridge is not None {
        b = bridge as PluginBridge;
        try {
            agate = agent_start_gate(b, message);
        } except Exception {
            agate = {"message": "", "systemPrompt": ""};
        }
        injected_system = str(agate.get("systemPrompt", ""));
        if injected_system {
            for i in range(len(history)) {
                if str(history[i].get("role", "")) == "system" {
                    sys_idx = i;
                    saved_sys = str(history[i].get("content", ""));
                    history[i]["content"] = injected_system;
                    break;
                }
            }
        }
        inj_msg = str(agate.get("message", ""));
        if inj_msg {
            history.append({"role": "user", "content": inj_msg});
        }
        fire_hook(b, "turn_start", {"message": message});
        fire_hook(b, "agent_start", {"message": message});
    }
    answer = "";
    turn_cancel = TurnCancel();
    plugins.active_cancel = turn_cancel;
    try {
        reg = plugins.reg if plugins.reg is not None else default_registry();
        answer = react_loop(
            history,
            [],
            transport,
            relay_tool_hooks(bridge, on_event),
            max_iters=max_iters,
            reg=reg,
            bridge=bridge,
            cancel=turn_cancel,
            approve=approve,
        );
    } finally {
        plugins.active_cancel = None;
        if sys_idx >= 0 {
            try {
                history[sys_idx]["content"] = saved_sys;
            } except Exception {}
        }
        if on_event is render_event {
            sys.stdout.write("\n");
            if show_stats {
                sys.stdout.write(f"  [{time.time() - _t0:.1f}s - {_n_tools} tools]\n");
            }
            sys.stdout.flush();
        } else {
            on_event("turn_end", {"secs": time.time() - _t0, "tools": _n_tools});
        }
        if bridge is not None {
            b2 = bridge as PluginBridge;
            fire_hook(
                b2, "turn_end", {"secs": time.time() - _t0, "tools": _n_tools, "answer": answer}
            );
            fire_hook(b2, "agent_end", {"answer": answer});
            fire_hook(b2, "agent_settled", {});
            _apply_extension_traffic(b2, on_event);
        }
        try {
            if not is_valid_session_id(plugins.session_id) {
                plugins.session_id = new_session_id();
            }
            save_session(plugins.cwd or os.getcwd(), history, session_id=plugins.session_id);
        } except Exception {}
    }
    if answer and on_event is not None {
        xres = transform_markdown(bridge, answer);
        shown = str(xres.get("markdown", answer)) if xres.get("ok") else answer;
        on_event("message", {"role": "assistant", "content": shown});
        if bridge is not None {
            try {
                mr: dict[str, any] = render_extension_block(
                    bridge as PluginBridge,
                    "message",
                    "assistant",
                    {"role": "assistant", "content": shown},
                );
                if mr.get("ok") and mr.get("lines") {
                    on_event(
                        "entry",
                        {
                            "type": "extension_render",
                            "render_type": "assistant",
                            "lines": mr["lines"],
                        },
                    );
                }
            } except Exception {}
        }
    }
    return answer;
}
