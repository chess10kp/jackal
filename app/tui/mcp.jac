"""MCP status window — first consumer of the tui/window API.

Pure over (specs, status): no agent.session import here, so this module
hosts its own test annex (tui/mcp.test.jac). The live glue (fetching
mcp_server_specs + plugins.mcp_status, the restart action) lives in
tui/commands.jac, which already imports the agent facade.

Replaces the old picker-based overlay and its hand-copied config parser
(_local_mcp_server_specs — deleted; agent.session_config.mcp_server_specs
is the public alias) and the tui/overlays.test.jac replica (deleted; this
annex is the real coverage)."""
import from tui.window { WindowSpec, WindowState, window_lines }


"""MCP window rows from configured specs + live status.

specs: {name: argv} from agent.session_config.mcp_server_specs (the
walk-up .jackal config). status: plugins.mcp_status — {state, error,
tools, cmd} per server, written by the attach/restart flow. A server can
be config-only (never attached), status-only (attached but not in
config), or both. Rows are sorted by name; the empty state names the
config convention. Returns {"rows": [...], "ids": [...]} with ids[i] the
server name for rows[i] ("" for the furniture row)."""
def mcp_window_rows(
    specs: dict[str, list[str]], status: dict[str, dict[str, any]]
) -> dict[str, list[str]] {
    rows: list[str] = [];
    ids: list[str] = [];
    declared: dict[str, bool] = {};
    for name in sorted(specs) {
        declared[str(name)] = True;
    }
    for name in sorted(status) {
        declared.setdefault(str(name), True);
    }
    for name in sorted(declared) {
        sname: str = str(name);
        st: dict[str, any] = status.get(sname, {}) if isinstance(status.get(sname, {}), dict) else {};
        state: str = str(st.get("state", ""));
        cmd: any = st.get("cmd") if st.get("cmd") else specs.get(sname, []);
        cmd_parts: list[str] = [];
        if isinstance(cmd, list) {
            for c in cmd {
                cmd_parts.append(str(c));
            }
        }
        cmd_label: str = " ".join(cmd_parts);
        if state == "connected" {
            denied_n: int = int(st.get("denied", 0) or 0);
            row: str = sname + " — connected · " + str(st.get("tools", 0)) + " tools";
            if denied_n > 0 {
                row += " · " + str(denied_n) + " denied";
            }
            rows.append(row + " · " + cmd_label);
        } elif state == "connecting" {
            rows.append(sname + " — connecting… · " + cmd_label);
        } elif state == "failed" {
            rows.append(sname + " — failed: " + str(st.get("error", "")) + " · " + cmd_label);
        } elif state {
            rows.append(sname + " — " + state + " · " + cmd_label);
        } else {
            rows.append(sname + " — configured · not connected · " + cmd_label);
        }
        ids.append(sname);
    }
    if not rows {
        rows.append("no mcp servers configured (.jackal: \"mcp\": {\"servers\": …})");
        ids.append("");
    }
    return {"rows": rows, "ids": ids};
}


"""Build the MCP STATUS window state over live data."""
def _mcp_window_state(
    specs: dict[str, list[str]], status: dict[str, dict[str, any]]
) -> WindowState {
    entries = mcp_window_rows(specs, status);
    has_servers: bool = False;
    if entries["ids"] and str(entries["ids"][0]) != "" {
        has_servers = True;
    }
    return WindowState(
        spec=WindowSpec(
            title="MCP STATUS",
            hint="\u2191\u2193 select · r restart · esc close",
        ),
        rows=list(entries["rows"]),
        ids=[str(x) for x in entries["ids"]],
        selected=0 if has_servers else -1,
        keys={"r": "restart"},
    );
}
