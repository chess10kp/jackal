"""Unit tests for tui/mcp.jac (same-stem annex; imports live in the stem).
Guards the MCP status window contract: honest per-state rows over
(specs, status), name-sorted, ids aligned with rows for the restart action,
and the empty state naming the config convention."""



test "connected server shows tools and command" {
    out = mcp_window_rows(
        {"zeta": ["jac", "mcp"]},
        {"zeta": {"state": "connected", "error": "", "tools": 3, "cmd": ["jac", "mcp"]}},
    );
    assert out["rows"] == ["zeta — connected · 3 tools · jac mcp"], str(out["rows"]);
    assert out["ids"] == ["zeta"];
}


test "connecting and failed states surface their live status" {
    out = mcp_window_rows(
        {"a": ["toolserv"]},
        {
            "a": {"state": "failed", "error": "spawn ENOENT", "tools": 0, "cmd": ["toolserv"]},
            "b": {"state": "connecting", "error": "", "tools": 0, "cmd": ["jac", "mcp"]},
        },
    );
    rows: list[str] = [str(r) for r in out["rows"]];
    assert "a — failed: spawn ENOENT · toolserv" in rows, str(rows);
    assert "b — connecting… · jac mcp" in rows, str(rows);
    assert out["ids"] == ["a", "b"];
}


test "config-only server reports not connected; status-only reports attached shape" {
    out = mcp_window_rows(
        {"alpha": ["toolserv"]},
        {"ghost": {"state": "connected", "error": "", "tools": 1, "cmd": ["g"]}},
    );
    rows: list[str] = [str(r) for r in out["rows"]];
    # alpha: configured, never attached (no status entry, state "").
    assert "alpha — configured · not connected · toolserv" in rows, str(rows);
    # ghost: live but absent from config — status-only falls back to the
    # bare state label with its own cmd.
    assert "ghost — connected · 1 tools · g" in rows, str(rows);
}


test "rows are name-sorted regardless of insertion order" {
    out = mcp_window_rows(
        {"zeta": ["z"], "alpha": ["a"]},
        {},
    );
    assert out["ids"] == ["alpha", "zeta"], str(out["ids"]);
    assert out["rows"][0].startswith("alpha —"), out["rows"][0];
    assert out["rows"][1].startswith("zeta —"), out["rows"][1];
}


test "empty state names the config convention and carries a furniture id" {
    out = mcp_window_rows({}, {});
    assert len(out["rows"]) == 1;
    assert "no mcp servers configured" in out["rows"][0], out["rows"][0];
    assert out["ids"] == [""];
}


test "window state wires the restart key and a cursor only over real rows" {
    live = _mcp_window_state(
        {"zeta": ["jac", "mcp"]},
        {"zeta": {"state": "connected", "error": "", "tools": 2, "cmd": ["jac", "mcp"]}},
    );
    assert live.spec.title == "MCP STATUS";
    assert live.selected == 0;
    assert live.keys == {"r": "restart"};
    assert live.ids == ["zeta"];

    empty = _mcp_window_state({}, {});
    assert empty.selected == -1;
    assert empty.ids == [""];
    lines = window_lines(empty);
    assert any("no mcp servers configured" in ln for ln in lines), str(lines);
}

test "connected row shows denied count when tools were filtered" {
    out = mcp_window_rows(
        {"zeta": ["jac", "mcp"]},
        {"zeta": {"state": "connected", "error": "", "tools": 2, "denied": 4, "cmd": ["jac", "mcp"]}},
    );
    assert out["rows"] == ["zeta — connected · 2 tools · 4 denied · jac mcp"], str(out["rows"]);
    # zero denied stays out of the row
    out2 = mcp_window_rows(
        {"zeta": ["jac", "mcp"]},
        {"zeta": {"state": "connected", "error": "", "tools": 2, "denied": 0, "cmd": ["jac", "mcp"]}},
    );
    assert out2["rows"] == ["zeta — connected · 2 tools · jac mcp"], str(out2["rows"]);
}


test "disabled servers surface their config state" {
    out = mcp_window_rows(
        {"off": ["toolserv"]},
        {"off": {"state": "disabled", "error": "", "tools": 0, "cmd": ["toolserv"]}},
    );
    rows: list[str] = [str(r) for r in out["rows"]];
    assert "off — disabled · toolserv" in rows, str(rows);
}
