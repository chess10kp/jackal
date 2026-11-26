impl set_mode(next_mode: str) -> str {
    if next_mode not in DEV_MODES {
        raise ValueError(
            "invalid mode '" + next_mode + "' (expected normal, auto-accept, yolo, plan, or ask)"
        );
    }
    set_mode_state(next_mode);
    return get_mode_state();
}

impl get_mode -> str {
    return get_mode_state();
}

impl _mcp_name_chunk(raw: any) -> str {
    s = str(raw);
    out = "".join([c if (c.isalnum() or c == "_") else "_" for c in s]);
    return out or "srv";
}

impl _mcp_server_specs(cfg: dict[str, any]) -> dict[str, dict[str, any]] {
    out: dict[str, dict[str, any]] = {};
    raw: any = cfg.get("mcp") if isinstance(cfg, dict) else None;
    if not isinstance(raw, dict) {
        return out;
    }
    servers: any = raw.get("servers");
    if not isinstance(servers, dict) {
        return out;
    }
    for (name, ent) in servers.items() {
        if not isinstance(ent, dict) or not str(name) {
            continue;
        }
        stype: str = "stdio";
        raw_type: any = ent.get("type", "stdio");
        if isinstance(raw_type, str) and str(raw_type).strip() {
            stype = str(raw_type).strip().lower();
        }
        env: dict[str, str] = {};
        raw_env: any = ent.get("env");
        if isinstance(raw_env, dict) {
            for (env_k, env_v) in raw_env.items() {
                env[str(env_k)] = str(env_v);
            }
        }
        cwd: str = str(ent.get("cwd", "") or "");
        enabled: bool = True;
        raw_enabled: any = ent.get("enabled", True);
        if isinstance(raw_enabled, bool) {
            enabled = raw_enabled;
        }
        timeout: float = -1.0;
        raw_to: any = ent.get("timeout");
        if isinstance(raw_to, (int, float)) and float(raw_to) > 0.0 {
            timeout = float(raw_to);
        }
        read_only: bool = False;
        raw_ro: any = ent.get("read_only", False);
        if isinstance(raw_ro, bool) {
            read_only = raw_ro;
        }
        read_only_tools: list[str] = [];
        raw_rot: any = ent.get("read_only_tools");
        if isinstance(raw_rot, list) {
            for pat in raw_rot {
                read_only_tools.append(str(pat));
            }
        }
        allow_tools: list[str] = [];
        raw_allow: any = ent.get("allow_tools");
        if isinstance(raw_allow, list) {
            for pat in raw_allow {
                allow_tools.append(str(pat));
            }
        }
        deny_tools: list[str] = [];
        raw_deny: any = ent.get("deny_tools");
        if isinstance(raw_deny, list) {
            for pat in raw_deny {
                deny_tools.append(str(pat));
            }
        }
        if stype in ("http", "streamable-http", "streamable_http") {
            url: str = str(ent.get("url", "") or "");
            if not url.startswith(("http://", "https://")) {
                continue;
            }
            headers: dict[str, str] = {};
            raw_hdrs: any = ent.get("headers");
            if isinstance(raw_hdrs, dict) {
                for (hk, hv) in raw_hdrs.items() {
                    headers[str(hk)] = str(hv);
                }
            }
            out[str(name)] = {
                "type": "http",
                "cmd": [],
                "url": url,
                "headers": headers,
                "env": env,
                "cwd": cwd,
                "enabled": enabled,
                "timeout": timeout,
                "read_only": read_only,
                "read_only_tools": read_only_tools,
                "allow_tools": allow_tools,
                "deny_tools": deny_tools,
            };
            continue;
        }
        cmd: any = ent.get("command");
        if isinstance(cmd, str) {
            cmd = [cmd];
        }
        if not isinstance(cmd, list) or not cmd {
            continue;
        }
        parts: list[str] = [str(c) for c in cmd];
        extra: any = ent.get("args");
        if isinstance(extra, list) {
            parts.extend([str(a) for a in extra]);
        }
        out[str(name)] = {
            "type": "stdio",
            "cmd": parts,
            "url": "",
            "headers": {},
            "env": env,
            "cwd": cwd,
            "enabled": enabled,
            "timeout": timeout,
            "read_only": read_only,
            "read_only_tools": read_only_tools,
            "allow_tools": allow_tools,
            "deny_tools": deny_tools,
        };
    }
    return out;
}

impl _make_mcp_handler(client: McpClient, server_name: str, tool_name: str) -> Callable[[
    dict[str, any],
], str] {
    def handle(args: dict[str, any]) -> str {
        res: dict[str, any] = client.call_tool(tool_name, args);
        if not res.get("ok") and not mcp_is_alive(client) {
            if _revive_client(server_name) {
                res = client.call_tool(tool_name, args);
            }
        }
        if res.get("ok") {
            if res.get("is_error") {
                return (
                    "ERROR: mcp tool "
                    + tool_name
                    + " on "
                    + server_name
                    + " failed: "
                    + str(res.get("result", ""))
                );
            }
            return str(res.get("result", ""));
        }
        return "ERROR: " + str(res.get("error", "mcp call failed"));
    }
    return handle as Callable[[dict[str, any]], str];
}

impl _make_mcp_resource_handler(client: McpClient, server_name: str) -> Callable[[
    dict[str, any],
], str] {
    def handle(args: dict[str, any]) -> str {
        uri: str = str(args.get("uri", ""));
        res: dict[str, any] = mcp_read_resource(client, uri);
        if not res.get("ok") and not mcp_is_alive(client) {
            if _revive_client(server_name) {
                res = mcp_read_resource(client, uri);
            }
        }
        if res.get("ok") {
            return str(res.get("text", ""));
        }
        return "ERROR: " + str(res.get("error", "resource read failed"));
    }
    return handle as Callable[[dict[str, any]], str];
}

impl _register_resource_tool(reg: ToolRegistry, server_name: str, client: McpClient) -> int {
    listed = mcp_list_resources(client, timeout_s=5.0);
    if not listed.get("ok") {
        return 0;
    }
    raw_res: any = listed.get("resources", []);
    if not isinstance(raw_res, list) or not raw_res {
        return 0;
    }
    sprefix: str = _mcp_name_chunk(server_name);
    full_name: str = "mcp_" + sprefix + "_read_resource";
    if get_tool(reg, full_name) is not None {
        plugins.mcp_notices.append(
            "mcp server "
                + server_name
                + " exposes resources but its own "
                + full_name
                + " tool wins; no generated resource reader",
        );
        return 0;
    }
    try {
        register_native(
            reg,
            full_name,
            "Read one resource by URI from mcp server "
                + server_name
                + ". Run /mcp resources "
                + server_name
                + " for the URI list.",
            {"type": "object", "properties": {"uri": {"type": "string"}}, "required": ["uri"]},
            _make_mcp_resource_handler(client, server_name),
        );
    } except Exception {
        return 0;
    }
    plugins.mcp_owned[full_name] = server_name;
    register_mcp_read_only_tools([full_name]);
    owned_ro: list[str] = list(plugins.mcp_read_only.get(server_name, []));
    if full_name not in owned_ro {
        owned_ro.append(full_name);
        plugins.mcp_read_only[server_name] = owned_ro;
    }
    return 1;
}

impl mcp_server_specs(cfg: dict[str, any]) -> dict[str, list[str]] {
    rich = _mcp_server_specs(cfg);
    out: dict[str, list[str]] = {};
    for (name, spec) in rich.items() {
        if str(spec.get("type", "stdio")) == "http" {
            out[name] = [str(spec.get("url", ""))];
        } else {
            out[name] = [str(c) for c in spec["cmd"]];
        }
    }
    return out;
}

impl _user_config_path -> str {
    agent_dir: str = os.environ.get("JACKAL_AGENT_DIR", "");
    if agent_dir {
        cand: str = os.path.join(agent_dir, "config.json");
        if os.path.isfile(cand) {
            return cand;
        }
    }
    home: str = os.path.expanduser("~");
    home_cand: str = os.path.join(home, ".jackal", "config.json");
    if os.path.isfile(home_cand) {
        return home_cand;
    }
    return "";
}

impl _load_json_dict(path: str) -> dict[str, any] {
    out: dict[str, any] = {};
    if not path or not os.path.isfile(path) {
        return out;
    }
    try {
        with open(path, "r", encoding="utf-8") as fh {
            parsed = json.load(fh);
        }
        if isinstance(parsed, dict) {
            out = parsed;
        }
    } except Exception {}
    return out;
}

impl mcp_config(cwd: str) -> dict[str, any] {
    user: dict[str, any] = _load_json_dict(_user_config_path());
    proj: dict[str, any] = load_project_config(cwd);
    raw_u: any = user.get("mcp");
    raw_p: any = proj.get("mcp");
    um: dict[str, any] = raw_u if isinstance(raw_u, dict) else {};
    pm: dict[str, any] = raw_p if isinstance(raw_p, dict) else {};
    merged: dict[str, any] = dict(um);
    for (key, val) in pm.items() {
        if key == "servers" and isinstance(val, dict) {
            raw_us: any = merged.get("servers");
            us: dict[str, any] = raw_us if isinstance(raw_us, dict) else {};
            servers: dict[str, any] = dict(us);
            for (sname, sent) in val.items() {
                servers[sname] = sent;
            }
            merged["servers"] = servers;
        } else {
            merged[key] = val;
        }
    }
    return {"mcp": merged};
}

impl mcp_configured_specs -> dict[str, list[str]] {
    cwd: str = plugins.cwd or os.getcwd();
    return mcp_server_specs(mcp_config(cwd));
}

impl _legacy_mcp_sources(agent_dir: str) -> list[str] {
    home: str = os.path.expanduser("~");
    cands: list[str] = [];
    if agent_dir {
        cands.append(os.path.join(agent_dir, "mcp.json"));
    }
    cands.append(os.path.join(home, ".cursor", "mcp.json"));
    cands.append(os.path.join(home, ".config", "Code", "User", "mcp.json"));
    cands.append(os.path.join(home, "Library", "Application Support", "Code", "User", "mcp.json"));
    out: list[str] = [];
    for c in cands {
        if os.path.isfile(c) {
            out.append(c);
        }
    }
    return out;
}

impl mcp_import_legacy(home_dir: str = "", sources: list[str] = []) -> list[str] {
    home: str = home_dir or os.path.expanduser("~");
    imported: list[str] = [];
    try {
        if os.environ.get("JACKAL_MCP_NO_IMPORT", "") {
            return imported;
        }
        marker: str = os.path.join(home, ".jackal", "mcp_import_done");
        if os.path.isfile(marker) {
            return imported;
        }
        agent_dir: str = os.environ.get("JACKAL_AGENT_DIR", "");
        srcs: list[str] = sources or _legacy_mcp_sources(agent_dir);
        target: str = os.path.join(home, ".jackal", "config.json");
        if agent_dir {
            cand: str = os.path.join(agent_dir, "config.json");
            if os.path.isfile(cand) {
                target = cand;
            }
        }
        user_cfg: dict[str, any] = _load_json_dict(target);
        raw_um: any = user_cfg.get("mcp");
        um: dict[str, any] = raw_um if isinstance(raw_um, dict) else {};
        raw_us: any = um.get("servers");
        us: dict[str, any] = raw_us if isinstance(raw_us, dict) else {};
        cwd: str = plugins.cwd or os.getcwd();
        proj_cfg: dict[str, any] = load_project_config(cwd);
        proj_specs: dict[str, dict[str, any]] = _mcp_server_specs(proj_cfg);
        changed: bool = False;
        for src_path in srcs {
            legacy: dict[str, any] = _load_json_dict(src_path);
            raw_servers: any = legacy.get("mcpServers");
            if not isinstance(raw_servers, dict) {
                continue;
            }
            for (name, ent) in raw_servers.items() {
                sname: str = str(name);
                if not sname or not isinstance(ent, dict) {
                    continue;
                }
                if sname in us or sname in proj_specs {
                    continue;
                }
                raw_cmd: any = ent.get("command");
                if not isinstance(raw_cmd, (str, list)) or not raw_cmd {
                    continue;
                }
                server_entry: dict[str, any] = {};
                if isinstance(raw_cmd, str) {
                    server_entry["command"] = str(raw_cmd);
                } else {
                    parts: list[str] = [];
                    for c in raw_cmd {
                        parts.append(str(c));
                    }
                    server_entry["command"] = parts;
                }
                raw_args: any = ent.get("args");
                if isinstance(raw_args, list) {
                    args_out: list[str] = [];
                    for a in raw_args {
                        args_out.append(str(a));
                    }
                    server_entry["args"] = args_out;
                }
                raw_env: any = ent.get("env");
                if isinstance(raw_env, dict) {
                    env_out: dict[str, str] = {};
                    for (ek, ev) in raw_env.items() {
                        env_out[str(ek)] = str(ev);
                    }
                    server_entry["env"] = env_out;
                }
                if ent.get("disabled") is True {
                    server_entry["enabled"] = False;
                }
                us[sname] = server_entry;
                imported.append(sname);
                changed = True;
            }
        }
        if changed {
            um["servers"] = us;
            user_cfg["mcp"] = um;
            os.makedirs(os.path.dirname(target), exist_ok=True);
            tmp_write: str = target + ".tmp";
            with open(tmp_write, "w", encoding="utf-8") as fh {
                fh.write(json_pretty(json.dumps(user_cfg, sort_keys=True)));
                fh.write("\n");
            }
            os.replace(tmp_write, target);
        }
        os.makedirs(os.path.dirname(marker), exist_ok=True);
        with open(marker, "w", encoding="utf-8") as fh {
            fh.write("done\n");
        }
    } except Exception {}
    return imported;
}

impl _mcp_set_status(
    server_name: str,
    state: str,
    error: str = "",
    tools: int = 0,
    cmd: list[str] | None = None,
    denied: int = 0,
) {
    prev: dict[str, any] = plugins.mcp_status.get(server_name, {});
    plugins.mcp_status[server_name] = {
        "state": state,
        "error": error,
        "tools": tools,
        "cmd": cmd if cmd is not None else prev.get("cmd", []),
        "denied": denied or int(prev.get("denied", 0) or 0),
    };
}

impl _mcp_fail(server_name: str, error: str) {
    _mcp_set_status(server_name, "failed", error);
    plugins.mcp_notices.append(
        "mcp server "
            + server_name
            + " unavailable: "
            + error
            + " (/mcp for status, /mcp restart "
            + server_name
            + " to retry)",
    );
}

impl _revive_client(server_name: str) -> bool {
    client: any = plugins.mcp_clients.get(server_name);
    if client is None {
        return False;
    }
    spec: dict[str, any] = dict(plugins.mcp_specs.get(server_name, {}));
    spec_type: str = str(spec.get("type", "stdio"));
    cmd: list[str] = [str(c) for c in spec.get("cmd", [])];
    if not cmd and spec_type != "http" {
        return False;
    }
    env_extra: dict[str, str] = {};
    raw_env: any = spec.get("env", {});
    if isinstance(raw_env, dict) {
        for (env_k, env_v) in raw_env.items() {
            env_extra[str(env_k)] = str(env_v);
        }
    }
    cwd: str = str(spec.get("cwd", "") or "");
    timeout: float = -1.0;
    raw_to: any = spec.get("timeout", -1.0);
    if isinstance(raw_to, (int, float)) {
        timeout = float(raw_to);
    }
    url: str = str(spec.get("url", "") or "");
    headers: dict[str, str] = {};
    raw_hdrs: any = spec.get("headers", {});
    if isinstance(raw_hdrs, dict) {
        for (hk, hv) in raw_hdrs.items() {
            headers[str(hk)] = str(hv);
        }
    }
    lock: any = _MCP_REVIVE_LOCK;
    lock.acquire();
    try {
        if client.initialized and mcp_is_alive(client) {
            return True;
        }
        mcp_stop(client);
        if spec_type == "http" {
            _mcp_set_status(server_name, "connecting", cmd=[url]);
            started = mcp_start_http(client, url, headers);
        } else {
            _mcp_set_status(server_name, "connecting", cmd=cmd);
            started = mcp_start(client, cmd, env_extra=env_extra, cwd=cwd);
        }
        if not started.get("ok") {
            _mcp_fail(server_name, str(started.get("error", "restart failed")));
            return False;
        }
        prev_tools: any = plugins.mcp_status.get(server_name, {}).get("tools", 0);
        _mcp_set_status(server_name, "connected", tools=int(prev_tools));
        plugins.mcp_notices.append(
            "mcp server " + server_name + " restarted after unexpected death"
        );
        return True;
    } finally {
        lock.release();
    }
}

impl mcp_health_check {
    for (name, client) in list(plugins.mcp_clients.items()) {
        st: dict[str, any] = plugins.mcp_status.get(name, {});
        if str(st.get("state", "")) != "connected" {
            continue;
        }
        if mcp_is_alive(client) {
            continue;
        }
        detail: str = "server process died unexpectedly";
        try {
            if client.proc is not None and client.proc.poll() is not None {
                detail += " (exit code " + str(client.proc.poll()) + ")";
            }
        } except Exception {}
        _mcp_fail(name, detail);
    }
}

impl drain_mcp_notices -> list[str] {
    mcp_health_check();
    mcp_pump_notifications();
    out: list[str] = list(plugins.mcp_notices);
    plugins.mcp_notices.clear();
    return out;
}

impl mcp_pump_notifications {
    for (name, client) in list(plugins.mcp_clients.items()) {
        st: dict[str, any] = plugins.mcp_status.get(name, {});
        if str(st.get("state", "")) != "connected" {
            continue;
        }
        notes_raw: any = None;
        try {
            notes_raw = mcp_drain_notifications(client);
        } except Exception {
            continue;
        }
        if not isinstance(notes_raw, list) {
            continue;
        }
        for note in notes_raw {
            if isinstance(note, dict)
                and str(note.get("method", "")) == "notifications/tools/list_changed"
            {
                _refresh_server_tools(name);
            }
        }
    }
}

impl _refresh_server_tools(server_name: str) {
    client: any = plugins.mcp_clients.get(server_name);
    reg = plugins.reg;
    if client is None or reg is None {
        return;
    }
    listed = mcp_list_tools(client, timeout_s=5.0);
    if not listed.get("ok") {
        plugins.mcp_notices.append(
            "mcp server "
                + server_name
                + " tools/list failed: "
                + str(listed.get("error", ""))
                + " (keeping current tools)",
        );
        return;
    }
    raw_tools: any = listed.get("tools", []);
    if not isinstance(raw_tools, list) {
        plugins.mcp_notices.append(
            "mcp server "
                + server_name
                + " tools/list returned no tool array (keeping current tools)",
        );
        return;
    }
    prefix: str = "mcp_" + _mcp_name_chunk(server_name) + "_";
    wanted_full: set[str] = set();
    for t in raw_tools {
        if isinstance(t, dict) and str(t.get("name", "")) {
            wanted_full.add(prefix + _mcp_name_chunk(str(t.get("name", ""))));
        }
    }
    removed: int = 0;
    for tname in list(reg.tools.keys()) {
        n: str = str(tname);
        mine: bool = plugins.mcp_owned.get(n, "") == server_name;
        if n.startswith(prefix) and mine and (n not in wanted_full) {
            if unregister(reg, n) {
                plugins.mcp_owned.pop(n, None);
                removed += 1;
            }
        }
    }
    spec: dict[str, any] = dict(plugins.mcp_specs.get(server_name, {}));
    stats = _register_server_tools(reg, server_name, client, spec, raw_tools);
    ro_names: list[str] = list(stats["ro_names"]);
    unregister_mcp_read_only_tools(list(plugins.mcp_read_only.get(server_name, [])));
    if ro_names {
        register_mcp_read_only_tools(ro_names);
    }
    n_res: int = _register_resource_tool(reg, server_name, client);
    plugins.mcp_read_only[server_name] = list(plugins.mcp_read_only.get(server_name, []));
    plugins.mcp_tools = max(0, plugins.mcp_tools - removed) + int(stats["registered"]) + n_res;
    _mcp_set_status(
        server_name,
        "connected",
        tools=int(stats["registered"]) + n_res,
        denied=int(stats["denied"]),
    );
    plugins.mcp_notices.append(
        "mcp server "
            + server_name
            + " tool list changed: +"
            + str(int(stats["registered"]))
            + " now registered, -"
            + str(removed)
            + " removed",
    );
}

impl _register_server_tools(
    reg: ToolRegistry, server_name: str, client: McpClient, spec: dict[str, any], tools: list[any]
) -> dict[str, any] {
    sprefix: str = _mcp_name_chunk(server_name);
    spec_read_only: bool = bool(spec.get("read_only", False));
    ro_globs: list[str] = [];
    raw_globs: any = spec.get("read_only_tools", []);
    if isinstance(raw_globs, list) {
        for pat in raw_globs {
            ro_globs.append(str(pat));
        }
    }
    registered: int = 0;
    lost: int = 0;
    lost_names: list[str] = [];
    ro_names: list[str] = [];
    denied: int = 0;
    denied_names: list[str] = [];
    allow_globs: list[str] = [];
    raw_allow: any = spec.get("allow_tools", []);
    if isinstance(raw_allow, list) {
        for pat in raw_allow {
            allow_globs.append(str(pat));
        }
    }
    deny_globs: list[str] = [];
    raw_deny: any = spec.get("deny_tools", []);
    if isinstance(raw_deny, list) {
        for pat in raw_deny {
            deny_globs.append(str(pat));
        }
    }
    for t in tools {
        if not isinstance(t, dict) {
            continue;
        }
        raw_tool: str = str(t.get("name", ""));
        tname = _mcp_name_chunk(raw_tool);
        if not tname {
            continue;
        }
        denied_hit: bool = False;
        for pat in deny_globs {
            if fnmatch.fnmatch(raw_tool, pat) {
                denied_hit = True;
                break;
            }
        }
        if not denied_hit and allow_globs {
            allowed_hit: bool = False;
            for pat in allow_globs {
                if fnmatch.fnmatch(raw_tool, pat) {
                    allowed_hit = True;
                    break;
                }
            }
            if not allowed_hit {
                denied_hit = True;
            }
        }
        if denied_hit {
            denied += 1;
            denied_names.append(raw_tool);
            continue;
        }
        schema: any = t.get("inputSchema");
        if not isinstance(schema, dict) or not schema {
            schema = {"type": "object", "properties": {}, "required": []};
        }
        full_name: str = "mcp_" + sprefix + "_" + tname;
        existing = get_tool(reg, full_name);
        if existing is not None and plugins.mcp_owned.get(full_name, "") != server_name {
            renamed: bool = False;
            for n in range(2, 51) {
                prev: str = full_name + "_" + str(n);
                if plugins.mcp_owned.get(prev, "") == server_name {
                    full_name = prev;
                    renamed = True;
                    break;
                }
            }
            if not renamed {
                for n in range(2, 51) {
                    cand: str = full_name + "_" + str(n);
                    if get_tool(reg, cand) is None {
                        full_name = cand;
                        renamed = True;
                        plugins.mcp_notices.append(
                            "mcp tool collision: "
                                + raw_tool
                                + " from "
                                + server_name
                                + " registered as "
                                + full_name,
                        );
                        break;
                    }
                }
            }
            if not renamed {
                lost += 1;
                lost_names.append(raw_tool);
                continue;
            }
        }
        ro_hit: bool = spec_read_only;
        if not ro_hit {
            for pat in ro_globs {
                if fnmatch.fnmatch(raw_tool, pat) {
                    ro_hit = True;
                    break;
                }
            }
        }
        if ro_hit {
            ro_names.append(full_name);
        }
        try {
            register_native(
                reg,
                full_name,
                str(t.get("description", "")),
                schema,
                _make_mcp_handler(client, server_name, raw_tool),
            );
            plugins.mcp_owned[full_name] = server_name;
            registered += 1;
        } except Exception {
            lost += 1;
            lost_names.append(raw_tool);
        }
    }
    if ro_names {
        register_mcp_read_only_tools(ro_names);
    }
    return {
        "registered": registered,
        "lost": lost,
        "lost_names": lost_names,
        "ro_names": ro_names,
        "denied": denied,
        "denied_names": denied_names,
    };
}

impl _attach_one_mcp_server(server_name: str, spec_json: str) {
    try {
        reg = plugins.reg;
        if reg is None {
            return;
        }
        parsed_spec: any = None;
        try {
            parsed_spec = json.loads(spec_json);
        } except Exception {
            parsed_spec = None;
        }
        if not isinstance(parsed_spec, dict) {
            _mcp_fail(server_name, "attach spec did not parse");
            return;
        }
        spec: dict[str, any] = parsed_spec;
        stale_ro: list[str] = list(plugins.mcp_read_only.get(server_name, []));
        if stale_ro {
            unregister_mcp_read_only_tools(stale_ro);
        }
        plugins.mcp_read_only[server_name] = [];
        cmd: list[str] = [str(c) for c in spec.get("cmd", [])];
        env_extra: dict[str, str] = {};
        raw_env: any = spec.get("env", {});
        if isinstance(raw_env, dict) {
            for (env_k, env_v) in raw_env.items() {
                env_extra[str(env_k)] = str(env_v);
            }
        }
        cwd: str = str(spec.get("cwd", "") or "");
        timeout: float = -1.0;
        raw_to: any = spec.get("timeout", -1.0);
        if isinstance(raw_to, (int, float)) {
            timeout = float(raw_to);
        }
        spec_type: str = str(spec.get("type", "stdio"));
        url: str = str(spec.get("url", "") or "");
        headers: dict[str, str] = {};
        raw_hdrs: any = spec.get("headers", {});
        if isinstance(raw_hdrs, dict) {
            for (hk, hv) in raw_hdrs.items() {
                headers[str(hk)] = str(hv);
            }
        }
        if spec_type == "http" {
            _mcp_set_status(server_name, "connecting", cmd=[url]);
        } else {
            _mcp_set_status(server_name, "connecting", cmd=cmd);
        }
        if timeout > 0.0 {
            client = create_mcp_client(timeout_s=timeout);
        } else {
            client = create_mcp_client();
        }
        plugins.mcp_clients[server_name] = client;
        if spec_type == "http" {
            started = mcp_start_http(client, url, headers);
        } else {
            started = mcp_start(client, cmd, env_extra=env_extra, cwd=cwd);
        }
        if not started.get("ok") {
            _mcp_fail(server_name, str(started.get("error", "spawn failed")));
            return;
        }
        listed = mcp_list_tools(client);
        if not listed.get("ok") {
            _mcp_fail(server_name, "tools/list failed: " + str(listed.get("error", "")));
            return;
        }
        raw_tools: any = listed.get("tools", []);
        if not isinstance(raw_tools, list) {
            _mcp_fail(server_name, "tools/list returned no tool array");
            return;
        }
        stats = _register_server_tools(reg, server_name, client, spec, raw_tools);
        plugins.mcp_read_only[server_name] = list(stats["ro_names"]);
        n_res: int = _register_resource_tool(reg, server_name, client);
        plugins.mcp_tools += int(stats["registered"]) + n_res;
        if int(stats["lost"]) > 0 {
            plugins.mcp_notices.append(
                "mcp server "
                    + server_name
                    + " lost "
                    + str(stats["lost"])
                    + " tool(s) to unresolvable name collisions: "
                    + ", ".join([str(x) for x in stats["lost_names"]]),
            );
        }
        if int(stats["denied"]) > 0 {
            plugins.mcp_notices.append(
                "mcp server "
                    + server_name
                    + " denied "
                    + str(stats["denied"])
                    + " tool(s) by allow_tools/deny_tools: "
                    + ", ".join([str(x) for x in stats["denied_names"]]),
            );
        }
        _mcp_set_status(
            server_name,
            "connected",
            tools=int(stats["registered"]) + n_res,
            denied=int(stats["denied"]),
        );
    } except Exception as e {
        _mcp_fail(server_name, "attach failed: " + str(e));
    }
}

impl _attach_mcp_servers {
    cwd: str = plugins.cwd or os.getcwd();
    imported: list[str] = mcp_import_legacy();
    if imported {
        plugins.mcp_notices.append(
            "mcp: imported "
                + str(len(imported))
                + " server(s) from legacy"
                + " mcp.json sources: "
                + ", ".join(imported)
                + " (user-level config; remove entries there or set"
                + " JACKAL_MCP_NO_IMPORT=1 to opt out)",
        );
    }
    specs = _mcp_server_specs(mcp_config(cwd));
    for (name, spec) in specs.items() {
        plugins.mcp_specs[name] = dict(spec);
        cmd: list[str] = [str(c) for c in spec["cmd"]];
        if str(spec.get("type", "stdio")) == "http" {
            cmd = [str(spec.get("url", ""))];
        }
        if not spec["enabled"] {
            _mcp_set_status(name, "disabled", cmd=cmd);
            continue;
        }
        _mcp_set_status(name, "connecting", cmd=cmd);
        flow _attach_one_mcp_server(name, json.dumps(spec));
    }
}

impl mcp_restart(server_name: str) -> str {
    spec: dict[str, any] = dict(plugins.mcp_specs.get(server_name, {}));
    st: dict[str, any] = plugins.mcp_status.get(server_name, {});
    is_http: bool = str(spec.get("type", "")) == "http";
    cmd: any = spec.get("cmd") if spec.get("cmd") else st.get("cmd", []);
    if is_http and not spec.get("url") {
        return "unknown mcp server: " + server_name;
    }
    if not is_http and (not isinstance(cmd, list) or not cmd) {
        return "unknown mcp server: " + server_name;
    }
    if not spec {
        spec = {
            "cmd": [str(c) for c in cmd],
            "env": {},
            "cwd": "",
            "enabled": True,
            "timeout": -1.0,
        };
    }
    old: any = plugins.mcp_clients.get(server_name);
    if old is not None {
        try {
            mcp_stop(old);
        } except Exception {}
        plugins.mcp_clients.pop(server_name, None);
    }
    reg = plugins.reg;
    if reg is not None {
        prefix: str = "mcp_" + _mcp_name_chunk(server_name) + "_";
        removed: int = 0;
        for tname in list(reg.tools.keys()) {
            if str(tname).startswith(prefix) and unregister(reg, str(tname)) {
                removed += 1;
                plugins.mcp_owned.pop(str(tname), None);
            }
        }
        plugins.mcp_tools = max(0, plugins.mcp_tools - removed);
    }
    restart_cmd: list[str] = (
        [str(spec.get("url", ""))] if is_http else [str(c) for c in spec.get("cmd", cmd)]
    );
    _mcp_set_status(server_name, "connecting", cmd=restart_cmd);
    spec_wire: str = json.dumps(spec);
    flow _attach_one_mcp_server(server_name, spec_wire);
    return "restarting mcp server " + server_name;
}

impl mcp_resources(server_name: str, uri: str) -> str {
    if uri {
        client: any = plugins.mcp_clients.get(server_name);
        if client is None {
            return "ERROR: unknown mcp server: " + server_name;
        }
        res = mcp_read_resource(client, uri);
        if not res.get("ok") {
            return "ERROR: " + str(res.get("error", "resources/read failed"));
        }
        return str(res.get("text", ""));
    }
    names: list[str] = [];
    if server_name {
        if server_name not in plugins.mcp_clients {
            return "ERROR: unknown mcp server: " + server_name;
        }
        names.append(server_name);
    } else {
        for name in sorted(plugins.mcp_clients.keys()) {
            names.append(str(name));
        }
    }
    lines: list[str] = [];
    for name in names {
        client2: any = plugins.mcp_clients.get(name);
        listed = mcp_list_resources(client2, timeout_s=5.0);
        if not listed.get("ok") {
            continue;
        }
        raw_res: any = listed.get("resources", []);
        if not isinstance(raw_res, list) or not raw_res {
            continue;
        }
        lines.append(name + ":");
        for r in raw_res {
            line: str = "  " + str(r.get("uri", ""));
            nm: str = str(r.get("name", ""));
            if nm {
                line += " — " + nm;
            }
            mt: str = str(r.get("mimeType", ""));
            if mt {
                line += " (" + mt + ")";
            }
            lines.append(line);
        }
    }
    if not lines {
        return "no mcp resources";
    }
    return "\n".join(lines);
}

impl mcp_prompt(server_name: str, prompt_name: str, args_json: str) -> str {
    client: any = plugins.mcp_clients.get(server_name);
    if client is None {
        return "ERROR: unknown mcp server: " + server_name;
    }
    args: dict[str, any] = {};
    trimmed: str = args_json.strip();
    if trimmed {
        parsed: any = None;
        try {
            parsed = json.loads(trimmed);
        } except Exception {
            return "ERROR: prompt args must be valid JSON";
        }
        if not isinstance(parsed, dict) {
            return "ERROR: prompt args must be a JSON object";
        }
        args = parsed;
    }
    res = mcp_get_prompt(client, prompt_name, args);
    if not res.get("ok") {
        return "ERROR: " + str(res.get("error", "prompts/get failed"));
    }
    parts: list[str] = [];
    raw_msgs: any = res.get("messages", []);
    if isinstance(raw_msgs, list) {
        for m in raw_msgs {
            if not isinstance(m, dict) {
                continue;
            }
            content: any = m.get("content");
            if isinstance(content, dict) and str(content.get("type", "")) == "text" {
                parts.append(
                    "[" + str(m.get("role", "user")) + "] " + str(content.get("text", ""))
                );
            }
        }
    }
    if not parts {
        return "ERROR: prompt returned no text messages";
    }
    return "\n".join(parts);
}

impl mcp_restart_failed -> str {
    doomed: list[str] = [];
    for name in sorted(plugins.mcp_status.keys()) {
        if str(plugins.mcp_status[name].get("state", "")) == "failed" {
            doomed.append(str(name));
        }
    }
    if not doomed {
        return "no failed mcp servers";
    }
    for name in doomed {
        mcp_restart(name);
    }
    return "restarting mcp servers: " + ", ".join(doomed);
}

impl wait_mcp_ready(timeout_s: float = -1.0) -> bool {
    budget: float = timeout_s;
    if budget < 0.0 {
        raw: str = os.environ.get("JACKAL_MCP_WAIT_S", "");
        try {
            budget = float(raw) if raw else 10.0;
        } except ValueError {
            budget = 10.0;
        }
    }
    deadline: float = time.time() + budget;
    while True {
        pending: bool = False;
        for st in list(plugins.mcp_status.values()) {
            if str(st.get("state", "")) == "connecting" {
                pending = True;
                break;
            }
        }
        if not pending {
            return True;
        }
        if time.time() >= deadline {
            return False;
        }
        time.sleep(0.05);
    }
    return False;
}

impl mcp_status_lines -> list[str] {
    lines: list[str] = [];
    for name in sorted(plugins.mcp_status.keys()) {
        st = plugins.mcp_status[name];
        state: str = str(st.get("state", ""));
        line: str = "  " + str(name) + " — " + state;
        if state == "connected" {
            line += " · " + str(st.get("tools", 0)) + " tools";
        }
        if state == "failed" {
            line += ": " + str(st.get("error", ""));
        }
        lines.append(line);
    }
    return lines;
}

impl _model_prefs_path -> str {
    cwd = plugins.cwd or os.getcwd();
    return os.path.join(cwd, ".jackal", "model_prefs.json");
}

impl _load_model_prefs {
    if _model_prefs_loaded {
        return;
    }
    path = _model_prefs_path();
    if not os.path.isfile(path) {
        return;
    }
    try {
        with open(path, "r") as fh {
            raw = json.load(fh);
        }
        if isinstance(raw, dict) {
            adopt_model_prefs(raw);
        }
    } except (OSError, ValueError) {}
}

impl _record_model_pref(name: str) {
    try {
        _load_model_prefs();
        _model_prefs["last"] = name;
        _model_prefs[provider_for(name)] = name;
        prefs_dir = os.path.join(plugins.cwd or os.getcwd(), ".jackal");
        os.makedirs(prefs_dir, exist_ok=True);
        path = os.path.join(prefs_dir, "model_prefs.json");
        with open(path, "w") as fh {
            fh.write(json_pretty(json.dumps(_model_prefs, sort_keys=True)));
            fh.write("\n");
        }
    } except Exception {}
}

impl model_preferences -> dict[str, any] {
    _load_model_prefs();
    return dict(_model_prefs);
}

impl set_model(name: str) -> str {
    err = credential_error(name);
    if err {
        return err;
    }
    set_model_state(name);
    _record_model_pref(name);
    b = plugins.bridge;
    if b is not None {
        try {
            fire_hook(b as PluginBridge, "model_select", {"model": name});
        } except Exception {}
    }
    return get_model_state();
}

impl set_thinking_level(level: str) -> str {
    set_thinking_level_state(level);
    b = plugins.bridge;
    if b is not None {
        try {
            fire_hook(b as PluginBridge, "thinking_level_select", {"level": level});
        } except Exception {}
    }
    return get_thinking_level_state();
}

impl clear_history {
    history.clear();
}

impl _apply_pending_model_requests {
    b = plugins.bridge;
    if b is None {
        return;
    }
    req: dict[str, any] = drain_model_requests(b as PluginBridge);
    m = str(req.get("model", ""));
    lv = str(req.get("thinking_level", ""));
    if m and m != get_model_state() {
        set_model(m);
    }
    if lv and lv != get_thinking_level_state() {
        set_thinking_level(lv);
    }
}
