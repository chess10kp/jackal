"""Rendering helpers for the interactive live shell demo."""

import from ui.transcript {
    materialize_visible,
}

import from ui.demo_live_shell_model { LiveShell }

import from ui.width {
    display_width,
    truncate_text,
}
glob SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];


def _rule(width: int, ch: str = "─") -> str {
    if width < 1 {
        return "";
    }
    return ch * width;
}


def _pad_to(text: str, width: int) -> str {
    w = display_width(text);
    if w >= width {
        return truncate_text(text, width, ellipsis="…");
    }
    return text + (" " * (width - w));
}


"""Block progress meter — denser than ASCII #/-."""
def _meter(value: float, width: int) -> str {
    if width < 3 {
        return "▪" * max(0, width);
    }
    inner = width - 2;
    filled = int(max(0.0, min(1.0, value)) * float(inner));
    if filled > inner {
        filled = inner;
    }
    return "▐" + ("█" * filled) + ("░" * (inner - filled)) + "▌";
}


def:pub _header_lines(app: LiveShell) -> list[str] {
    brand = " JACKAL ";
    tag = " osp live ";
    right = (
        str(app.columns)
        + "×"
        + str(app.rows)
        + "  r"
        + str(app.session.graph_revision)
    );
    mid_pad = app.columns - display_width(brand) - display_width(tag) - display_width(right) - 2;
    if mid_pad < 1 {
        mid_pad = 1;
    }
    top = brand + tag + (" " * mid_pad) + right;
    return [_pad_to(top, app.columns), _rule(app.columns, "━")];
}


def:pub _status_line(app: LiveShell) -> str {
    spin = SPINNER[app.spin_i % len(SPINNER)];
    phase: str = app.phase;
    if app.phase == "streaming" {
        phase = spin + " stream";
    } elif app.phase == "approval" {
        phase = "◈ approve";
    } elif app.phase == "ready" {
        phase = "● ready";
    }
    meter = _meter(app.progress_value, 14);
    left = phase + "  " + meter;
    right = app.status_hint;
    gap = app.columns - display_width(left) - display_width(right) - 2;
    if gap < 1 {
        return truncate_text(left + "  " + right, app.columns, ellipsis="…");
    }
    return left + (" " * gap) + right;
}


def:pub _approval_lines(app: LiveShell) -> list[str] {
    _ = app;
    inner = 46;
    return [
        "╭" + _rule(inner, "─") + "╮",
        "│" + _pad_to("  TOOL APPROVAL", inner) + "│",
        "│" + _pad_to("", inner) + "│",
        "│" + _pad_to("  jac check  app/ui/renderer.jac", inner) + "│",
        "│" + _pad_to("  mode       read-only verify", inner) + "│",
        "│" + _pad_to("", inner) + "│",
        "│" + _pad_to("  [a] Accept    [r] Reject    [esc]", inner) + "│",
        "╰" + _rule(inner, "─") + "╯",
    ];
}


def:pub _transcript_lines(app: LiveShell) -> list[str] {
    win = materialize_visible(app.proj);
    if win.lines {
        return win.lines;
    }
    # Empty-state composition — one quiet invitation.
    w = max(10, app.columns - 2);
    return [
        "",
        truncate_text("  the graph is live.", w, ellipsis="…"),
        truncate_text("  type below — jackal answers in this frame.", w, ellipsis="…"),
        "",
        truncate_text("  try:  explain retained damage", w, ellipsis="…"),
    ];
}
