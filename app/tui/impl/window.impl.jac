impl _wpad(text: str, width: int) -> str {
    w = display_width(text);
    if w >= width {
        return truncate_text(text, width, ellipsis="…");
    }
    return text + (" " * (width - w));
}

impl window_frame(spec: WindowSpec, body: list[str]) -> list[str] {
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

impl window_view(rows: list[str], selected: int, max_rows: int) -> tuple[list[str], int] {
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

impl window_lines(state: WindowState) -> list[str] {
    body: list[str] = [];
    if state.selected >= 0 {
        pair: tuple[list[str], int] = window_view(state.rows, state.selected, state.spec.max_rows);
        body = pair[0];
    } else {
        body = list(state.rows);
    }
    return window_frame(state.spec, body);
}
