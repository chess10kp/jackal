impl mcp_window_rows(
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
        st: dict[str, any] = status.get(sname, {})
            if isinstance(status.get(sname, {}), dict)
            else {};
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

impl _mcp_window_state(
    specs: dict[str, list[str]], status: dict[str, dict[str, any]]
) -> WindowState {
    entries = mcp_window_rows(specs, status);
    has_servers: bool = False;
    if entries["ids"] and str(entries["ids"][0]) != "" {
        has_servers = True;
    }
    return WindowState(
        spec=WindowSpec(title="MCP STATUS", hint="\u2191\u2193 select · r restart · esc close"),
        rows=list(entries["rows"]),
        ids=[str(x) for x in entries["ids"]],
        selected=0 if has_servers else -1,
        keys={"r": "restart"},
    );
}
