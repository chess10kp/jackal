"""Painting and overlay rendering for the native LiveShell."""
import os;
import from tui.state { LiveShell }
import from tui.core {
    _rule, _pad_to, _prompt_prefix, _prompt_lines,
}
import from core.edit { compute_unified_diff }
import from ui.model { UiNode }
import from ui.transcript { materialize_visible }
import from ui.layout { LayoutSpec, OverlayAnchor, fill_axis, fixed_axis }
import from ui.renderer {
    render_frame, set_node_content, set_node_contract,
    mark_semantic_dirty, mark_layout_dirty, request_cursor,
}
import from ui.width { display_width, truncate_text }
import from tui.picker_base { _picker_filtered }
import from tui.windows {  _picker_state, _window_paint_lines, _ui_modal_state, _approval_state }
import from agent.session { get_model, model_preferences }
import from agent.llm { PROVIDER_ROUTES, catalog_models, routed_model_id, provider_for }
import from tui.window { WindowSpec, window_frame, window_view }
"""Unified-diff preview lines for a pending write_file/edit_file approval.
Capped at 20 diff lines with a trailing truncation marker; returns [] when
no old/new text pair can be assembled (missing args, unreadable baseline)."""
def _approval_diff_preview(name: str, args: dict[str, any]) -> list[str] {
    old_text = "";
    new_text = "";
    if name == "edit_file" {
        old_text = str(args.get("old_text", ""));
        new_text = str(args.get("new_text", ""));
    } elif name == "write_file" {
        new_text = str(args.get("content", ""));
        path = str(args.get("path", ""));
        if path {
            full = path if os.path.isabs(path) else os.path.join(os.getcwd(), path);
            # Baseline is read from disk at render time (preview only);
            # a missing file means every line is an addition.
            if os.path.isfile(full) {
                try {
                    fh = open(full);
                    old_text = fh.read();
                    fh.close();
                } except Exception {
                    return [];
                }
            }
        } else {
            return [];
        }
    } else {
        return [];
    }
    diff = compute_unified_diff(old_text, new_text);
    if not diff or diff.startswith("ERROR") {
        return [];
    }
    raw: list[str] = diff.split("\n");
    cap = 20;
    shown: list[str] = raw[:cap];
    out: list[str] = ["diff:"];
    for ln in shown {
        prefix = " ";
        if ln.startswith("+") or ln.startswith("-") or ln.startswith("@") {
            prefix = "";
        }
        out.append(prefix + ln);
    }
    more = len(raw) - cap;
    if more > 0 {
        out.append("…  +" + str(more) + " lines");
    }
    return out;
}


"""Approval overlay body — REAL pending-approval data: tool name plus cmd
(run_command), target path and old/new char counts (write_file/edit_file)
or generic key=value pairs, then a capped unified-diff preview."""
def _approval_lines(app: LiveShell) -> list[str] {
    inner = 46;
    approval: any = _approval_state(app);
    tool_name = str(approval.get("tool", "?"));
    args: any = approval.get("args", {});
    head = "TOOL APPROVAL · " + tool_name;
    body: list[str] = [];
    if isinstance(args, dict) {
        if tool_name == "run_command" {
            body.append("$ " + str(args.get("cmd", "")));
            timeout_secs = str(args.get("timeout_secs", ""));
            if timeout_secs {
                body.append("timeout " + timeout_secs + "s");
            }
        } elif tool_name == "write_file" {
            body.append(str(args.get("path", "")));
            body.append("+ " + str(len(str(args.get("content", "")))) + " chars");
        } elif tool_name == "edit_file" {
            body.append(str(args.get("path", "")));
            body.append(
                "- " + str(len(str(args.get("old_text", ""))))
                + " / + " + str(len(str(args.get("new_text", "")))) + " chars"
            );
        } else {
            parts: list[str] = [];
            for pair in args.items() {
                parts.append(str(pair[0]) + "=" + str(pair[1])[:40]);
            }
            body.append((", ".join(parts))[:inner - 6]);
        }
        body.extend(_approval_diff_preview(tool_name, args));
    }
    if not body {
        body.append("(no details available)");
    }
    body = [""] + body;
    body.append("");
    body.append("  [a] Accept    [r] Reject    [esc]");
    return window_frame(WindowSpec(title=head, width=inner), body);
}


"""Foreground extension-ui modal content — painted into the shared
overlay node while app.ui_modal is set."""
def _ui_modal_lines(app: LiveShell) -> list[str] {
    m: any = _ui_modal_state(app);
    inner = 46;
    method = str(m.get("method", ""));
    head = "? [ui] " + method.upper();
    body: list[str] = [];
    title = str(m.get("title", ""));
    message = str(m.get("message", ""));
    placeholder = str(m.get("placeholder", ""));
    if title {
        body.append(title[:inner - 4]);
    }
    if message {
        body.append(message[:inner - 4]);
    }
    body.append("");
    if method == "select" {
        options: list[any] = list(m.get("options", []));
        sel = int(m.get("selected", 0));
        i = 0;
        for opt in options[:8] {
            mark = ">" if i == sel else " ";
            body.append(mark + " " + str(opt)[:inner - 6]);
            i += 1;
        }
        body.append("");
        body.append("  [\u2191\u2193] move   [enter] choose   [esc] cancel");
    } elif method == "confirm" {
        body.append("  [y] yes    [n/Esc] no");
    } else {
        draft = str(m.get("draft", ""));
        shown = draft if draft else placeholder;
        body.append("  > " + shown[:inner - 6] + "\u258c");
        body.append("");
        body.append("  [enter] submit (empty allowed)   [esc] cancel");
    }
    return window_frame(WindowSpec(title=head, width=inner), body);
}


"""Prompt-anchored drop-up for every explicit picker.
The same selection pattern handles provider login, sessions, skills, tasks,
checkpoints, explorer, and extension select requests."""
def _picker_popup_rows(app: LiveShell) -> list[str] {
    p: any = _picker_state(app);
    if p is None {
        return [];
    }
    width = max(12, app.columns - 2);
    title = str(p.get("title", "CHOICE"));
    out: list[str] = [truncate_text("⌃ " + title, width, ellipsis="…")];
    if str(p.get("mode", "select")) == "input" {
        draft = str(p.get("draft", ""));
        if title == "LOGIN" {
            shown = ("*" * len(draft)) if draft else "(paste API key)";
            out.append(truncate_text("  " + str(p.get("providerId", "")), width, ellipsis="…"));
        } else {
            shown = draft if draft else "(type a value)";
        }
        out.append(truncate_text("> " + shown + "▌", width, ellipsis="…"));
        out.append("Enter submit · Esc cancel");
        return out;
    }
    vis: tuple[list[str], list[str]] = _picker_filtered(p);
    labels: list[str] = [];
    opts = vis[0];
    ids = vis[1];
    toggled: list[str] = list(p.get("toggled", []));
    for i in range(len(opts)) {
        label = str(opts[i]);
        if bool(p.get("multi", False)) {
            rid = str(ids[i]) if i < len(ids) else "";
            label = ("[x] " if rid in toggled else "[ ] ") + label;
        }
        labels.append(label);
    }
    if str(p.get("filter", "")) {
        out.append(truncate_text("/ " + str(p.get("filter", "")), width, ellipsis="…"));
    }
    if labels {
        max_rows = min(6, max(1, app.rows // 3));
        view: tuple[list[str], int] = window_view(labels, int(p.get("selected", 0)), max_rows);
        out.extend([truncate_text(row, width, ellipsis="…") for row in view[0]]);
    } else {
        out.append("(no matches)");
    }
    if bool(p.get("multi", False)) {
        out.append("↑↓ move · type filter · Space toggle · Enter choose · Esc close");
    } else {
        out.append("↑↓ move · type filter · Enter choose · Esc close");
    }
    return [truncate_text(row, width, ellipsis="…") for row in out];
}


"""Prompt-anchored drop-up for extension select requests."""
def _ui_select_popup_rows(app: LiveShell) -> list[str] {
    m: any = _ui_modal_state(app);
    if m is None {
        return [];
    }
    options: list[any] = list(m.get("options", []));
    filt = str(m.get("filter", ""));
    q = filt.lower();
    labels: list[str] = [];
    for option in options {
        label = str(option);
        if not q or q in label.lower() {
            labels.append(label);
        }
    }
    width = max(12, app.columns - 2);
    title = str(m.get("title", "")) or str(m.get("message", "SELECT"));
    out: list[str] = [truncate_text("⌃ " + title, width, ellipsis="…")];
    if filt {
        out.append(truncate_text("/ " + filt, width, ellipsis="…"));
    }
    if labels {
        max_rows = min(6, max(1, app.rows // 3));
        view: tuple[list[str], int] = window_view(labels, int(m.get("selected", 0)), max_rows);
        out.extend([truncate_text(row, width, ellipsis="…") for row in view[0]]);
    } else {
        out.append("(no matches)");
    }
    out.append("↑↓ move · type filter · Enter choose · Esc cancel");
    return [truncate_text(row, width, ellipsis="…") for row in out];
}


"""Paint a centered modal/approval into the shared overlay node.
The caller has already decided ownership; this guards the optional node."""
def _paint_overlay(app: LiveShell, lines: list[str], outer_width: int = 48) {
    ov: UiNode | None = app.shell.approval;
    if ov is None {
        return;
    }
    set_node_contract(
        app.renderer,
        ov,
        LayoutSpec(
            width=fixed_axis(outer_width),
            height=fixed_axis(len(lines)),
            overlay_anchor=OverlayAnchor.CENTER,
        ),
    );
    set_node_content(app.renderer, ov, lines);
    mark_semantic_dirty(app.renderer, ov);
    mark_layout_dirty(app.renderer, ov);
}


# ==================== model completion ====================

"""Model candidates for the `/model <prefix>` completion window.

Pool is the same live catalog the old picker used (catalog_models per
provider, routed_model_id, per-provider last-used from model_preferences,
plus the active model). Filtering is case-insensitive substring on the
typed prefix, capped at 8 so the popup stays compact. Each entry is
["/model <id>", provider_description] — the prompt handler replaces the
whole draft with the chosen label. Pure over the catalog."""
def _model_completion_candidates(prefix: str) -> list[list[str]] {
    p = prefix.strip().lower();
    pool: list[str] = [];
    seen: dict[str, bool] = {};
    prefs: dict[str, any] = {};
    try {
        prefs = dict(model_preferences());
    } except Exception {
        prefs = {};
    }
    for prov in PROVIDER_ROUTES {
        models = catalog_models(str(prov));
        for m in models {
            mid = routed_model_id(str(prov), str(m));
            if mid not in seen {
                seen[mid] = True;
                pool.append(mid);
            }
        }
        last = str(prefs.get(str(prov), "") or "");
        if last and last not in seen {
            seen[last] = True;
            pool.append(last);
        }
    }
    active = get_model();
    if active and active not in seen {
        pool.insert(0, active);
        seen[active] = True;
    }
    filtered: list[str] = [];
    if not p {
        filtered = pool[:8];
    } else {
        for mid in pool {
            if p in mid.lower() {
                filtered.append(mid);
                if len(filtered) >= 8 {
                    break;
                }
            }
        }
    }
    out: list[list[str]] = [];
    for mid in filtered {
        prov = provider_for(mid);
        desc = "";
        route: any = PROVIDER_ROUTES.get(prov);
        if isinstance(route, dict) {
            desc = str(route.get("description", "") or "");
        }
        out.append(["/model " + mid, desc]);
    }
    return out;
}


"""Dismissal gate for the slash/model popup. The dismissed value is the
RAW draft captured at esc/tab/enter time, and the popup stays hidden only
while the draft is unchanged. This used to compare the STRIPPED draft,
which merges "/model" with "/model ": after tab-completing /model (or
dismissing with esc), typing the argument space never reopened the
window. Pure so the rule stays testable headless."""
def _popup_suppressed(raw: str, dismissed: str) -> bool {
    return raw == dismissed;
}


"""Model completion visibility + candidates in one shot: hidden while any
modal, picker or approval owns the screen. The popup only appears for
`/model` and `/model <prefix>`, not as a global command-search palette."""
def _slash_popup_state(app: LiveShell) -> list[list[str]] | None {
    if _picker_state(app) is not None or _ui_modal_state(app) is not None or app.shell.approval is not None {
        return None;
    }
    raw = app.shell.prompt.draft;
    if _popup_suppressed(raw, app.slash_dismissed) {
        return None;
    }
    # Model argument completion: "/model" or "/model <prefix>" — same window
    trimmed_start = raw.lstrip();
    if trimmed_start.startswith("/model") {
        rest = trimmed_start[len("/model"):];
        if rest == "" or (rest and rest[0] == " ") {
            pref = rest.strip();
            cands = _model_completion_candidates(pref);
            if cands {
                return cands;
            }
            return None;
        }
    }
    return None;
}


"""Resolve a tab/enter press against model completion. Enter on a candidate
identical to the current draft returns submit=True, so /model can open on
one Enter. Pure so the decision stays testable headless."""
def _slash_popup_pick(matches: list[list[str]], draft: str, sel: int) -> tuple[str, bool] {
    count = len(matches);
    idx = int(sel);
    if idx >= count {
        idx = count - 1;
    }
    if idx < 0 {
        idx = 0;
    }
    chosen = str(matches[idx][0]);
    return (chosen, chosen == draft.strip());
}


""">-cursor rows for the popup (selected entry marked, description
truncated to the terminal width). Selection clamps into range so stale
indices from earlier filters never crash the paint."""
def _slash_popup_rows(app: LiveShell, matches: list[list[str]]) -> list[str] {
    max_w = max(10, app.columns - 2);
    sel = int(app.slash_sel);
    if sel >= len(matches) {
        sel = len(matches) - 1;
    }
    if sel < 0 {
        sel = 0;
    }
    rows: list[str] = [];
    i = 0;
    for m in matches {
        mark = ">" if i == sel else " ";
        label = str(m[0]);
        desc = str(m[1]);
        if desc {
            label += " — " + desc;
        }
        rows.append(truncate_text(mark + " " + label, max_w, ellipsis="…"));
        i += 1;
    }
    return rows;
}


def _transcript_lines(app: LiveShell) -> list[str] {
    win = materialize_visible(app.proj);
    if win.lines {
        return win.lines;
    }
    # Empty-state composition — one quiet invitation.
    w = max(10, app.columns - 2);
    return [
        "",
        truncate_text("  Jackal — native agent harness", w, ellipsis="…"),
        "",
        truncate_text("  Type a message below, or try /help for commands.", w, ellipsis="…"),
        "",
        truncate_text("  Example:  explain how the transcript layout works", w, ellipsis="…"),
        "",
    ];
}


def _paint(app: LiveShell) {
    lines = _transcript_lines(app);
    prompt_lines = _prompt_lines(app);

    # Choices and model completion render ABOVE the prompt box inside the
    # prompt node; its fixed contract grows/shrinks with the drop-up.
    popup: list[list[str]] | None = _slash_popup_state(app);
    popup_rows: list[str] = [];
    if _picker_state(app) is not None {
        popup_rows = _picker_popup_rows(app);
    } elif _ui_modal_state(app) is not None
        and str(_ui_modal_state(app).get("method", "")) == "select" {
        popup_rows = _ui_select_popup_rows(app);
    } elif popup is not None {
        popup_rows = _slash_popup_rows(app, popup);
    }
    set_node_contract(
        app.renderer,
        app.shell.prompt,
        LayoutSpec(
            width=fill_axis(),
            height=fixed_axis(3 + len(popup_rows)),
        ),
    );

    # Shared overlay node: real approvals take precedence; non-choice
    # extension modals use it. Pickers render in the prompt drop-up.
    overlay: list[str] | None = None;
    if app.phase == "approval" {
        overlay = _approval_lines(app);
    } elif _ui_modal_state(app) is not None
        and str(_ui_modal_state(app).get("method", "")) != "select" {
        overlay = _ui_modal_lines(app);
    }
    win_lines: list[str] | None = None;
    if overlay is None and _picker_state(app) is None
        and app.phase != "approval"
        and not (
            _ui_modal_state(app) is not None
            and str(_ui_modal_state(app).get("method", "")) == "select"
        ) {
        win_lines = _window_paint_lines(app);
        if win_lines is not None {
            _paint_overlay(app, win_lines, len(win_lines[0]));
        }
    }
    if overlay is not None {
        _paint_overlay(app, overlay);
    }

    set_node_content(app.renderer, app.shell.transcript, lines);
    set_node_content(app.renderer, app.shell.prompt, popup_rows + prompt_lines);
    mark_semantic_dirty(app.renderer, app.shell.transcript);
    mark_semantic_dirty(app.renderer, app.shell.prompt);
    mark_layout_dirty(app.renderer, app.shell.screen);

    # Caret sits after the mode prefix + draft inside the box (col 1 is │).
    prefix_w = display_width(_prompt_prefix(app.mode));
    draft_w = display_width(app.shell.prompt.draft);
    cursor_col = 1 + prefix_w + draft_w;
    max_col = app.columns - 2;
    if cursor_col > max_col {
        cursor_col = max_col;
    }
    request_cursor(
        app.renderer,
        app.shell.prompt,
        row_offset=1 + len(popup_rows),
        col_offset=cursor_col,
    );
}


def _render(app: LiveShell) {
    if not app.dirty {
        return;
    }
    _paint(app);
    frame = render_frame(app.renderer, app.shell.screen, app.term);
    if frame.cursor_row >= 0 {
        app.term.show_cursor();
    } else {
        app.term.hide_cursor();
    }
    app.dirty = False;
}
