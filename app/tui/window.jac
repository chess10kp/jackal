"""General windowing primitives for the LiveShell overlay layer.

Pure and import-free below ui.width: this leaf hosts its own test annex
(tui/window.test.jac). Real TUI modules cannot host annexes (they pull the
demoted ui.terminal/virtual_terminal seams — see tui/popup_pick.jac), so
window chrome/viewport math lives here and side-effecting hosts stay out
(tui/windows.jac owns the LiveShell stack, keys and paint bridge).

The API is declarative: a WindowSpec describes chrome, a WindowState carries
data + behavior hooks, window_lines() renders. First consumer: the MCP
status window (tui/mcp.jac). Existing pickers/modals migrate later.
"""
import from ui.width { display_width, truncate_text }

# Anchor placement stays in
# the host's _paint_overlay (all current windows are centered).


obj WindowSpec {
    has title: str = "",
        width: int = 46,
        hint: str = "",
        max_rows: int = 8;
}


obj WindowState {
    has spec: WindowSpec,
        # Owner tag lets the stack host specialized interaction state.
        kind: str = "window",
        # Owner-specific mutable data; picker is the first stack-owned case.
        payload: any = None,
        rows: list[str] = [],
        # ids[i] is the action payload for rows[i] ("" for furniture rows).
        ids: list[str] = [],
        # Cursor into rows; -1 = no cursor, no viewport (plain info window).
        selected: int = -1,
        # key name -> action name, resolved through on_action.
        keys: dict[str, str] = {},
        # fn(app, win, action) -> feedback line ("" = silent).
        on_action: any = None,
        # fn(app, win) — re-read live data before paint (status windows).
        refresh: any = None;
}


def _wpad(text: str, width: int) -> str {
    w = display_width(text);
    if w >= width {
        return truncate_text(text, width, ellipsis="…");
    }
    return text + (" " * (width - w));
}


"""One framed window: ╭─╮ title / body rows / hint footer / ╰─╯.

Body lines longer than spec.width are truncated with an ellipsis. The hint
footer (plus its blank separator) is emitted only when spec.hint is set."""
def window_frame(spec: WindowSpec, body: list[str]) -> list[str] {
    lines: list[str] = [
        "╭" + ("─" * spec.width) + "╮",
        "│" + _wpad("  " + spec.title, spec.width) + "│",
    ];
    for ln in body {
        lines.append("│" + _wpad("  " + ln, spec.width) + "│");
    }
    if spec.hint {
        lines.append("│" + _wpad("", spec.width) + "│");
        lines.append("│" + _wpad("  " + spec.hint, spec.width) + "│");
    }
    lines.append("╰" + ("─" * spec.width) + "╯");
    return lines;
}


"""Sliding viewport over rows for a cursor position.

selected < 0 (or a short list) shows every row verbatim. Otherwise the
cursor row is kept visible: the window scrolls only when the cursor leaves
the viewport (selection-stable, like the existing pickers), '… N more'
markers mark truncated tails, and the cursor gets a '> ' mark. Returns
(display rows, scroll offset)."""
def window_view(
    rows: list[str], selected: int, max_rows: int
) -> tuple[list[str], int] {
    count = len(rows);
    if count == 0 {
        return ([], 0);
    }
    sel = int(selected);
    if sel < 0 or count <= max_rows {
        out: list[str] = [];
        i = 0;
        for r in rows {
            if sel >= 0 and i == sel {
                out.append("> " + r);
            } elif sel >= 0 {
                out.append("  " + r);
            } else {
                out.append(r);
            }
            i += 1;
        }
        return (out, 0);
    }
    sel = min(sel, count - 1);
    offset = sel - (max_rows - 1);
    if offset < 0 {
        offset = 0;
    }
    visible: list[str] = rows[offset:offset + max_rows];
    out2: list[str] = [];
    if offset > 0 {
        out2.append("… " + str(offset) + " more");
    }
    i = offset;
    for r in visible {
        if i == sel {
            out2.append("> " + r);
        } else {
            out2.append("  " + r);
        }
        i += 1;
    }
    below = count - offset - max_rows;
    if below > 0 {
        out2.append("… " + str(below) + " more");
    }
    return (out2, offset);
}


"""Render a WindowState: viewport + frame in one call."""
def window_lines(state: WindowState) -> list[str] {
    body: list[str] = [];
    if state.selected >= 0 {
        pair: tuple[list[str], int] = window_view(
            state.rows, state.selected, state.spec.max_rows
        );
        body = pair[0];
    } else {
        body = list(state.rows);
    }
    return window_frame(state.spec, body);
}
