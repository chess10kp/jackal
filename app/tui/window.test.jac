"""Unit tests for tui/window.jac (same-stem annex; imports live in the
stem). Guards the general windowing contract: uniform chrome, per-width
truncation, the selection-stable sliding viewport with more-markers, and
cursor/no-cursor modes."""



test "frame draws title, body and an exact box" {
    spec = WindowSpec(title="T", width=10, hint="esc close");
    lines = window_frame(spec, ["alpha", "beta"]);
    assert lines[0] == "╭" + "─" * 10 + "╮", lines[0];
    assert lines[1] == "│" + _wpad("  T", 10) + "│", lines[1];
    assert lines[2] == "│" + _wpad("  alpha", 10) + "│", lines[2];
    assert lines[3] == "│" + _wpad("  beta", 10) + "│", lines[3];
    assert lines[4] == "│" + _wpad("", 10) + "│", lines[4];
    assert lines[5] == "│" + _wpad("  esc close", 10) + "│", lines[5];
    assert lines[6] == "╰" + "─" * 10 + "╯", lines[6];
}


test "frame omits the hint footer when hint is empty" {
    spec = WindowSpec(title="T", width=8);
    lines = window_frame(spec, ["x"]);
    assert len(lines) == 4, str(len(lines));
    assert lines[3] == "╰" + "─" * 8 + "╯", lines[3];
}


test "frame truncates overlong body lines to the inner width" {
    spec = WindowSpec(title="T", width=8);
    lines = window_frame(spec, ["0123456789abc"]);
    assert len(lines) == 4;
    assert lines[2].startswith("│  01234"), lines[2];
    assert lines[2].endswith("…│"), lines[2];
    assert len(lines[2]) == 10, lines[2];
}


test "short list with cursor shows every row marked, no markers" {
    (vis, off) = window_view(["a", "b"], 0, 8);
    assert vis == ["> a", "  b"], str(vis);
    assert off == 0;
}


test "no cursor renders rows verbatim" {
    (vis, off) = window_view(["a", "b"], -1, 8);
    assert vis == ["a", "b"], str(vis);
    assert off == 0;
}


test "long list scrolls only when the cursor leaves the viewport" {
    rows: list[str] = [];
    for i in range(1, 11) {
        rows.append("row " + str(i));
    }
    # Cursor at top: first max_rows rows, only a below-marker.
    (vis, off) = window_view(rows, 0, 8);
    assert len(vis) == 9, str(vis);
    assert vis[0] == "> row 1", vis[0];
    assert vis[7] == "  row 8", vis[7];
    assert vis[8] == "… 2 more", vis[8];
    assert off == 0;
    # Cursor at bottom: last max_rows rows, only an above-marker.
    (vis2, off2) = window_view(rows, 9, 8);
    assert vis2[0] == "… 2 more", vis2[0];
    assert vis2[1] == "  row 3", vis2[1];
    assert vis2[8] == "> row 10", vis2[8];
    assert off2 == 2;
    # Cursor in the middle stays put while visible; no markers at offset 0
    # until it passes the bottom edge.
    (vis3, off3) = window_view(rows, 6, 8);
    assert vis3[0] == "  row 1" or vis3[0] == "> row 7", vis3[0];
    assert off3 == 0;
    assert vis3[6] == "> row 7", vis3[6];
    assert vis3[8] == "… 2 more", vis3[8];
}


test "viewport clamps a stale cursor past the end" {
    rows: list[str] = [];
    for i in range(1, 13) {
        rows.append("r" + str(i));
    }
    (vis, off) = window_view(rows, 99, 8);
    assert vis[len(vis) - 1] == "> r12", vis[len(vis) - 1];
    assert off == 4;
}


test "empty rows render an empty body" {
    (vis, off) = window_view([], -1, 8);
    assert vis == [];
    assert off == 0;
}


test "window_lines composes viewport and frame" {
    rows: list[str] = [];
    for i in range(1, 13) {
        rows.append("r" + str(i));
    }
    state = WindowState(
        spec=WindowSpec(title="MCP", width=20, hint="esc"),
        rows=rows,
        selected=0,
    );
    lines = window_lines(state);
    assert lines[1] == "│" + _wpad("  MCP", 20) + "│", lines[1];
    assert lines[2] == "│" + _wpad("  > r1", 20) + "│", lines[2];
    assert lines[len(lines) - 2] == "│" + _wpad("  esc", 20) + "│", lines[len(lines) - 2];
}


test "window_lines without a cursor shows rows verbatim" {
    state = WindowState(
        spec=WindowSpec(title="INFO", width=10),
        rows=["plain"],
        selected=-1,
    );
    lines = window_lines(state);
    assert lines[2] == "│" + _wpad("  plain", 10) + "│", lines[2];
}
