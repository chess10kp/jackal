"""Session configuration, model preferences, and MCP attachment."""

import os;
import json;
import time;

import from .llm { provider_for, credential_error }
import from .modes { DEV_MODES }
import from .plugin_bridge { PluginBridge, fire_hook, drain_model_requests }
import from .registry { ToolRegistry, register_native, unregister }
import from .mcp {
    McpClient,
    create_mcp_client,
    mcp_start,
    mcp_list_tools,
    mcp_stop,
}
import from .session_state {
    history,
    model,
    thinking_level,
    mode,
    plugins,
    _model_prefs,
    _model_prefs_loaded,
    set_mode_state,
    get_mode_state,
    set_model_state,
    get_model_state,
    set_thinking_level_state,
    get_thinking_level_state,
    adopt_model_prefs,
}


def set_mode(next_mode: str) -> str {
    if next_mode not in DEV_MODES {
        raise ValueError(
            "invalid mode '" + next_mode
            + "' (expected normal, auto-accept, yolo, plan, or ask)"
        );
    }
    set_mode_state(next_mode);
    return get_mode_state();
}


"""Return the active dev mode for native UI clients."""
def get_mode() -> str {
    return get_mode_state();
}


def _mcp_name_chunk(raw: any) -> str {
    s = str(raw);
    out = "".join([c if (c.isalnum() or c == "_") else "_" for c in s]);
    return out if out else "srv";
}


"""Extract {name: argv} MCP server specs from a parsed .jackal config.
Malformed entries are skipped silently."""
def _mcp_server_specs(cfg: dict[str, any]) -> dict[str, list[str]] {
    out: dict[str, list[str]] = {};
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
        out[str(name)] = parts;
    }
    return out;
}


"""Handler factory closing over one client/server/tool triple.

Returns a native-tool handler whose string result mirrors the registry's
resultToString convention. It accepts one decoded argument dictionary so the
native dispatch path does not require dynamic keyword unpacking."""
def _make_mcp_handler(client: McpClient, server_name: str, tool_name: str) -> Callable[[dict[str, any]], str] {
    def handle(args: dict[str, any]) -> str {
        res: dict[str, any] = client.call_tool(tool_name, args);
        if res.get("ok") {
            if res.get("is_error") {
                return (
                    "ERROR: mcp tool " + tool_name + " on " + server_name
                    + " failed: " + str(res.get("result", ""))
                );
            }
            return str(res.get("result", ""));
        }
        return "ERROR: " + str(res.get("error", "mcp call failed"));
    }
    return handle as Callable[[dict[str, any]], str];
}


"""Public alias of _mcp_server_specs for UI modules (underscore names did
not bind across modules at runtime)."""
def mcp_server_specs(cfg: dict[str, any]) -> dict[str, list[str]] {
    return _mcp_server_specs(cfg);
}


def _mcp_set_status(server_name: str, state: str, error: str = "", tools: int = 0, cmd: list[str] | None = None) {
    prev: dict[str, any] = plugins.mcp_status.get(server_name, {});
    plugins.mcp_status[server_name] = {
        "state": state,
        "error": error,
        "tools": tools,
        "cmd": cmd if cmd is not None else prev.get("cmd", []),
    };
}


def _mcp_fail(server_name: str, error: str) {
    _mcp_set_status(server_name, "failed", error);
    plugins.mcp_notices.append(
        "mcp server " + server_name + " unavailable: " + error
        + " (/mcp for status, /mcp restart " + server_name + " to retry)"
    );
}


"""Pop queued MCP notices for display (frontends call this each tick/turn)."""
def drain_mcp_notices() -> list[str] {
    out: list[str] = list(plugins.mcp_notices);
    plugins.mcp_notices.clear();
    return out;
}


"""Spawn + initialize one MCP server, then seed namespaced tools into the
live registry. Runs inside a background flow — never raises; failures land
in plugins.mcp_status and plugins.mcp_notices (never printed: stdout belongs
to the TUI/JSONL frontends)."""
def _attach_one_mcp_server(server_name: str, cmd: list[str]) {
    try {
        reg = plugins.reg;
        if reg is None {
            return;
        }
        _mcp_set_status(server_name, "connecting", cmd=cmd);
        client = create_mcp_client();
        # Register the client before connecting so dispose can stop it even
        # mid-handshake.
        plugins.mcp_clients[server_name] = client;
        started = mcp_start(client, cmd);
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
        sprefix = _mcp_name_chunk(server_name);
        registered = 0;
        for t in raw_tools {
            if not isinstance(t, dict) {
                continue;
            }
            raw_tool: str = str(t.get("name", ""));
            tname = _mcp_name_chunk(raw_tool);
            if not tname {
                continue;
            }
            schema: any = t.get("inputSchema");
            if not isinstance(schema, dict) or not schema {
                schema = {"type": "object", "properties": {}, "required": []};
            }
            try {
                register_native(
                    reg,
                    "mcp_" + sprefix + "_" + tname,
                    str(t.get("description", "")),
                    schema,
                    _make_mcp_handler(client, server_name, raw_tool),
                );
                registered += 1;
            } except Exception {
            }
        }
        plugins.mcp_tools += registered;
        _mcp_set_status(server_name, "connected", tools=registered);
    } except Exception as e {
        _mcp_fail(server_name, "attach failed: " + str(e));
    }
}


"""Parse .jackal mcp config and background-spawn each declared server."""
def _attach_mcp_servers(cfg: dict[str, any]) {
    specs = _mcp_server_specs(cfg);
    for (name, cmd) in specs.items() {
        _mcp_set_status(name, "connecting", cmd=list(cmd));
        flow _attach_one_mcp_server(name, cmd);
    }
}


"""Stop a server's client and drop its tools, then spawn it again in the
background with the command it was configured with. Returns a status line."""
def mcp_restart(server_name: str) -> str {
    st: dict[str, any] = plugins.mcp_status.get(server_name, {});
    cmd: any = st.get("cmd", []);
    if not isinstance(cmd, list) or not cmd {
        return "unknown mcp server: " + server_name;
    }
    old: any = plugins.mcp_clients.get(server_name);
    if old is not None {
        try {
            mcp_stop(old);
        } except Exception {
        }
        plugins.mcp_clients.pop(server_name, None);
    }
    reg = plugins.reg;
    if reg is not None {
        prefix: str = "mcp_" + _mcp_name_chunk(server_name) + "_";
        removed: int = 0;
        for tname in list(reg.tools.keys()) {
            if str(tname).startswith(prefix) and unregister(reg, str(tname)) {
                removed += 1;
            }
        }
        plugins.mcp_tools = max(0, plugins.mcp_tools - removed);
    }
    # Same shape as _attach_mcp_servers: a typed spec map whose loop values
    # are sendable into the flow.
    specs: dict[str, list[str]] = {server_name: [str(c) for c in cmd]};
    for (name, argv) in specs.items() {
        _mcp_set_status(name, "connecting", cmd=list(argv));
        flow _attach_one_mcp_server(name, argv);
    }
    return "restarting mcp server " + server_name;
}


"""Block (bounded) until no MCP server is still connecting, so the first
model request sees every tool that is going to attach. Budget comes from
JACKAL_MCP_WAIT_S (default 10s). Returns True when nothing is pending."""
def wait_mcp_ready(timeout_s: float = -1.0) -> bool {
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
            if str(st.get("state", "")) == "connecting" { pending = True; break; }
        }
        if not pending { return True; }
        if time.time() >= deadline { return False; }
        time.sleep(0.05);
    }
    return False;
}


"""One status line per known MCP server (REPL /mcp)."""
def mcp_status_lines() -> list[str] {
    lines: list[str] = [];
    for name in sorted(plugins.mcp_status.keys()) {
        st = plugins.mcp_status[name];
        state: str = str(st.get("state", ""));
        line: str = "  " + str(name) + " — " + state;
        if state == "connected" { line += " · " + str(st.get("tools", 0)) + " tools"; }
        if state == "failed" { line += ": " + str(st.get("error", "")); }
        lines.append(line);
    }
    return lines;
}



def _model_prefs_path() -> str {
    cwd = plugins.cwd if plugins.cwd else os.getcwd();
    return os.path.join(cwd, ".jackal", "model_prefs.json");
}


"""One-time defensive load of model_prefs.json (missing/corrupt -> {})."""
def _load_model_prefs {
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
    } except (OSError, ValueError) {
    }
}


"""Record the last model overall ("last") and per provider, then persist
to <cwd>/.jackal/model_prefs.json best-effort. Never raises — a preference
write must never break a successful switch."""
def _record_model_pref(name: str) {
    try {
        _load_model_prefs();
        _model_prefs["last"] = name;
        _model_prefs[provider_for(name)] = name;
        prefs_dir = os.path.join(
            plugins.cwd if plugins.cwd else os.getcwd(), ".jackal"
        );
        os.makedirs(prefs_dir, exist_ok=True);
        path = os.path.join(prefs_dir, "model_prefs.json");
        with open(path, "w") as fh {
            json.dump(_model_prefs, fh, indent=2, sort_keys=True);
            fh.write("\n");
        }
    } except Exception {
    }
}


"""Snapshot of persisted last-model preferences ("last" + provider keys).
For the TUI /model picker to preselect per-provider defaults."""
def model_preferences() -> dict[str, any] {
    _load_model_prefs();
    return dict(_model_prefs);
}


"""Switch the active model. Validates credentials fx-style BEFORE applying:
a model whose provider key is missing is refused and the actionable error
text is returned instead of the model name (callers render the returned
string directly). On success fires Pi's model_select hook best-effort so
listeners see every change regardless of source (/model command or an
extension's pi.setModel applied via _apply_pending_model_requests) and
records the per-provider/overall last-model preference."""
def set_model(name: str) -> str {
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
        } except Exception {
        }
    }
    return get_model_state();
}


"""Set the reasoning-effort level used for subsequent turns (empty = off).
The transport layer maps it to the request body's reasoning.effort. Fires
Pi's thinking_level_select hook best-effort, mirroring set_model."""
def set_thinking_level(level: str) -> str {
    set_thinking_level_state(level);
    b = plugins.bridge;
    if b is not None {
        try {
            fire_hook(b as PluginBridge, "thinking_level_select", {"level": level});
        } except Exception {
        }
    }
    return get_thinking_level_state();
}


def clear_history {
    history.clear();
}





"""Apply extension-issued model and thinking-level requests."""
def _apply_pending_model_requests() {
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
