impl _rule(width: int, ch: str = "─") -> str {
    if width < 1 {
        return "";
    }
    return ch * width;
}

impl _meter(value: float, width: int) -> str {
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

impl _next_id(app: LiveShell) -> str {
    app.msg_n += 1;
    return "m" + str(app.msg_n);
}

impl _commit_messages(app: LiveShell) {
    app.rev += 1;
    apply_transcript_revision(app.proj, app.rev, app.messages);
    app.dirty = True;
}

impl _push_turn(app: LiveShell, role: str, body: str) -> str {
    mid = _next_id(app);
    content = format_turn(role, body);
    if app.messages and role != "tool" {
        content = "\n" + content;
    }
    app.messages = app.messages + [
        TranscriptMessage(message_id=mid, content=content, content_rev=1),
    ];
    _commit_messages(app);
    return mid;
}

impl _rewrite_turn(app: LiveShell, message_id: str, role: str, body: str) {
    updated: list[TranscriptMessage] = [];
    for message in app.messages {
        if message.message_id == message_id {
            updated.append(
                TranscriptMessage(
                    message_id=message_id,
                    content=format_turn(role, body),
                    content_rev=message.content_rev + 1,
                ),
            );
        } else {
            updated.append(message);
        }
    }
    app.messages = updated;
    _commit_messages(app);
}

impl _finish_turn(app: LiveShell, message_id: str, role: str, body: str) {
    kept: list[TranscriptMessage] = [];
    found: bool = False;
    trailing: bool = False;
    for message in app.messages {
        if message.message_id == message_id {
            found = True;
        } else {
            if found {
                trailing = True;
            }
            kept.append(message);
        }
    }
    if not found or not trailing {
        _rewrite_turn(app, message_id, role, body);
        return;
    }
    kept.append(
        TranscriptMessage(message_id=_next_id(app), content=format_turn(role, body), content_rev=1)
    );
    app.messages = kept;
    _commit_messages(app);
}

impl _install_layout(app: LiveShell) {
    configure_main_shell_layout(app.renderer.layout, app.shell);
    set_node_contract(
        app.renderer, app.shell.header, LayoutSpec(width=fill_axis(), height=fixed_axis(0))
    );
    set_node_contract(
        app.renderer, app.shell.status, LayoutSpec(width=fill_axis(), height=fixed_axis(0))
    );
    set_node_contract(
        app.renderer, app.shell.prompt, LayoutSpec(width=fill_axis(), height=fixed_axis(2))
    );
}

impl _prompt_prefix(mode: str) -> str {
    if mode == "plan" {
        return "[plan] ❯ ";
    }
    if mode == "ask" {
        return "[ask] ❯ ";
    }
    return "❯ ";
}

impl _prompt_lines(app: LiveShell) -> list[str] {
    draft = app.shell.prompt.draft;
    w = app.columns;
    body = truncate_text(_prompt_prefix(app.mode) + draft, w, ellipsis="…");
    return [_rule(w), body];
}

impl _transcript_total_height(app: LiveShell) -> int {
    total = 0;
    for message in app.proj.messages {
        total += measure_message_height(app.proj, message, app.proj.viewport_width);
    }
    return total;
}

impl _scroll_transcript(app: LiveShell, delta: int) {
    proj = app.proj;
    if delta == 0 {
        return;
    }
    vh = max(1, proj.viewport_height);
    if delta > 0 and proj.view.follow_tail {
        return;
    }
    if delta < 0 and proj.view.follow_tail {
        set_follow_tail(proj, False);
    }
    total = _transcript_total_height(app);
    max_off = max(0, total - vh);
    off = min(max(0, proj.view.scroll_offset + delta), max_off);
    proj.view.scroll_offset = off;
    if off >= max_off and not proj.view.follow_tail {
        set_follow_tail(proj, True);
    }
    app.dirty = True;
}
