impl extensions_status -> ExtensionStatus {
    st = ExtensionStatus(
        phase=plugins.phase,
        loaded=plugins.loaded,
        total=plugins.total,
        ready=plugins.ready,
        detail=plugins.detail,
        t_interactive_s=plugins.t_interactive,
        t_ext_ready_s=plugins.t_ext_ready,
        compat_tier="",
    );
    b = plugins.bridge;
    if b is not None {
        st.compat_tier = b.compat_tier;
    }
    st.label = extensions_label(st);
    return st;
}

impl _warm_sidecar(base_cwd: str) {
    bridge = plugins.bridge;
    reg = plugins.reg;
    if bridge is None or reg is None {
        plugins.phase = "degraded";
        plugins.detail = "missing bridge/registry";
        plugins.ready = True;
        plugins.t_ext_ready = time.time();
        return;
    }
    try {
        plugins.phase = "starting";
        ensure_node_host(bridge);
        decls: list[ExtensionDecl] = node_sidecar_decls(plugins.decls);
        for d in decls {
            path = resolve_decl_path(d, base_cwd);
            load_extension_path(
                bridge, reg, d.id, path, requires=d.requires, has_ui=plugins.interactive_ui
            );
            plugins.loaded += 1;
            plugins.phase = "loading";
        }
        plugins.phase = "ready";
        plugins.ready = True;
        plugins.detail = "";
        plugins.t_ext_ready = time.time();
        plugins.commands.update(bridge.commands);
        fire_hook(bridge as PluginBridge, "session_start", {"session_id": plugins.session_id});
        try {
            fire_project_trust(bridge as PluginBridge, base_cwd);
        } except Exception {}
        res_paths: list[str] = [];
        for cand in [
            os.path.join(base_cwd, ".jackal", "skills"),
            os.path.join(base_cwd, "skills"),
            os.path.join(base_cwd, ".jackal", "prompts"),
            os.path.join(base_cwd, "prompts"),
        ] {
            if os.path.isdir(cand) {
                res_paths.append(cand);
            }
        }
        fire_hook(bridge as PluginBridge, "resources_discover", {"paths": res_paths});
    } except Exception as e {
        plugins.phase = "degraded";
        plugins.detail = str(e);
        plugins.ready = True;
        plugins.t_ext_ready = time.time();
        b = plugins.bridge;
        if b is not None {
            host_status(b);
        }
    }
}

impl session_boot(
    sid: str = "",
    cwd: str = "",
    decls: list[any] | None = None,
    wait_budget_s: float = 5.0,
    interactive_ui: bool = False,
) -> ExtensionStatus {
    requested_mode: str = os.environ.get("JACKAL_MODE", "");
    set_mode(requested_mode or "normal");
    plugins.session_id = sid or "session";
    plugins.cwd = cwd or os.getcwd();
    plugins.interactive_ui = interactive_ui;
    plugins.wait_budget_s = wait_budget_s;
    plugins.t_interactive = time.time();
    plugins.t_ext_ready = 0.0;
    plugins.loaded = 0;
    plugins.detail = "";
    plugins.prompt_queue.clear();
    plugins.warm_future = None;

    parsed: list[ExtensionDecl] = [];
    if decls is not None {
        for item in decls {
            if isinstance(item, ExtensionDecl) {
                parsed.append(item);
            } elif isinstance(item, dict) {
                parsed.append(decl_from_dict(item));
            }
        }
    } else {
        parsed = load_extension_decls(plugins.cwd);
    }
    plugins.decls = parsed;
    plugins.reg = default_registry();
    register_agent_tools(plugins.reg);
    rt = get_tool(plugins.reg, "run_command");
    if rt is not None and rt.handler is not None {
        cell: dict[str, any] = {"fn": rt.handler};

        def _run_command_hooked(args: dict[str, any]) -> str {
            cmd = str(args.get("cmd", ""));
            timeout_raw: any = args.get("timeout_secs", 120);
            timeout_secs = int(timeout_raw) if timeout_raw is not None else 120;
            res = str(cell["fn"]({"cmd": cmd, "timeout_secs": timeout_secs}));
            fire_user_bash(plugins.bridge as PluginBridge | None, cmd, res);
            return res;
        }
        rt.handler = _run_command_hooked;
    }
    plugins.mcp_status.clear();
    plugins.mcp_notices.clear();
    plugins.mcp_specs.clear();
    plugins.mcp_read_only.clear();
    plugins.mcp_owned.clear();
    try {
        _attach_mcp_servers();
    } except Exception {}
    _load_model_prefs();

    sidecar: list[ExtensionDecl] = node_sidecar_decls(parsed);
    plugins.total = len(sidecar);
    if plugins.total == 0 {
        plugins.bridge = None;
        plugins.ready = True;
        plugins.phase = "idle";
        plugins.t_ext_ready = plugins.t_interactive;
        return extensions_status();
    }

    plugins.bridge = create_bridge(plugins.session_id);
    plugins.ready = False;
    plugins.phase = "starting";
    warm_cwd: str = plugins.cwd;
    plugins.warm_future = flow _warm_sidecar(warm_cwd);
    return extensions_status();
}

impl wait_extensions_ready(timeout_s: float = -1.0) -> ExtensionStatus {
    budget = timeout_s if timeout_s >= 0.0 else plugins.wait_budget_s;
    if plugins.ready and plugins.warm_future is None {
        return extensions_status();
    }
    wf = plugins.warm_future;
    if wf is not None {
        try {
            if budget <= 0.0 {
                wait wf;
            } else {
                deadline = time.monotonic() + budget;
                while not plugins.ready and time.monotonic() < deadline {
                    time.sleep(0.02);
                }
            }
        } except Exception as e {
            plugins.phase = "degraded";
            plugins.detail = str(e);
            plugins.ready = True;
            if plugins.t_ext_ready <= 0.0 {
                plugins.t_ext_ready = time.time();
            }
        }
    }
    if not plugins.ready {
        plugins.phase = "degraded";
        if not plugins.detail {
            plugins.detail = f"extension wait budget {budget}s expired";
        }
        plugins.ready = True;
        if plugins.t_ext_ready <= 0.0 {
            plugins.t_ext_ready = time.time();
        }
    }
    return extensions_status();
}

impl enqueue_prompt(message: str) -> int {
    plugins.prompt_queue.append(message);
    return len(plugins.prompt_queue);
}

impl drain_prompt_queue -> list[str] {
    out: list[str] = list(plugins.prompt_queue);
    plugins.prompt_queue.clear();
    return out;
}

impl session_dispose {
    wf = plugins.warm_future;
    if wf is not None {
        try {
            wait wf;
        } except Exception {}
        plugins.warm_future = None;
    }
    for (_mc_name, mc) in plugins.mcp_clients.items() {
        try {
            mcp_stop(mc);
        } except Exception {}
    }
    plugins.mcp_clients.clear();
    plugins.mcp_tools = 0;
    plugins.mcp_status.clear();
    plugins.mcp_notices.clear();
    plugins.mcp_specs.clear();
    plugins.mcp_read_only.clear();
    plugins.mcp_owned.clear();
    b = plugins.bridge;
    if b is not None {
        try {
            fire_hook(b as PluginBridge, "session_shutdown", {});
        } except Exception {}
        dispose_bridge(b as PluginBridge);
        plugins.bridge = None;
    }
    plugins.reg = None;
    plugins.ready = True;
    plugins.phase = "idle";
    plugins.loaded = 0;
    plugins.total = 0;
    plugins.commands.clear();
}
