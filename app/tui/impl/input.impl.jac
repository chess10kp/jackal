impl _handle_picker_key(app: LiveShell, key: str) {
    p: any = _picker_state(app);
    if p is None {
        return;
    }
    title = str(p.get("title", ""));
    if key == "escape" {
        if str(p.get("mode", "select")) != "input" and str(p.get("filter", "")) {
            p["filter"] = "";
            p["selected"] = 0;
            app.dirty = True;
            return;
        }
        if title == "LOGIN" {
            _cancel_login(app);
            return;
        }
        if bool(p.get("multi", False)) and str(p.get("filter", "")) {
            p["filter"] = "";
            p["selected"] = 0;
            app.dirty = True;
            return;
        }
        _close_picker(app);
        return;
    }
    if str(p.get("mode", "select")) == "input" {
        draft = str(p.get("draft", ""));
        if key == "enter" {
            if title == "LOGIN" {
                _complete_api_key_login(app, str(p.get("providerId", "")), draft.strip());
            } else {
                _close_picker(app);
            }
        } elif key == "backspace" or key == "\x7f" {
            if draft {
                p["draft"] = draft[:-1];
                app.dirty = True;
            }
        } elif len(key) == 1 and key >= " " {
            p["draft"] = draft + key;
            app.dirty = True;
        }
        return;
    }
    options: list[str] = list(p.get("options", []));
    ids: list[str] = list(p.get("ids", []));
    is_multi: bool = bool(p.get("multi", False));
    filt: str = str(p.get("filter", ""));
    if key == "backspace" or key == "\x7f" {
        if filt {
            p["filter"] = filt[:-1];
            p["selected"] = 0;
            app.dirty = True;
        }
        return;
    }
    if len(key) == 1 and key >= " " and not (is_multi and key == " ") {
        p["filter"] = filt + key;
        p["selected"] = 0;
        app.dirty = True;
        return;
    }
    vis: tuple[list[str], list[str]] = _multi_filtered(p);
    options = vis[0];
    ids = vis[1];
    sel = int(p.get("selected", 0));
    if key == " " and is_multi and len(options) > 0 {
        idx = min(sel, len(options) - 1);
        rid = str(ids[idx]) if idx < len(ids) else "";
        if rid and rid != "__header__" {
            toggled: list[str] = list(p.get("toggled", []));
            if rid in toggled {
                toggled.remove(rid);
            } else {
                toggled.append(rid);
            }
            p["toggled"] = toggled;
            app.dirty = True;
        }
        return;
    }
    if (key == "up" or key == "k") and len(options) > 0 {
        p["selected"] = (sel - 1) % len(options);
        app.dirty = True;
    } elif (key == "down" or key == "j") and len(options) > 0 {
        p["selected"] = (sel + 1) % len(options);
        app.dirty = True;
    } elif key == "enter" and len(options) > 0 {
        idx = min(sel, len(options) - 1);
        chosen_id = str(ids[idx]) if idx < len(ids) else "";
        if chosen_id == "__type__" {
            p["mode"] = "input";
            p["draft"] = "";
            app.dirty = True;
            return;
        }
        if title == "LOGIN" {
            _start_login_provider(app, chosen_id);
            return;
        }
        if title == "LOGOUT" {
            _close_picker(app);
            reply = _run_slash(app, "/logout " + chosen_id);
            if reply {
                _push_turn(app, "tool", reply);
            }
            app.dirty = True;
            return;
        }
        if title == "DEV MODE" {
            _close_picker(app);
            app.mode = set_mode(chosen_id);
            app.dirty = True;
            return;
        }
        if chosen_id == "__header__" {
            app.dirty = True;
            return;
        }
        if bool(p.get("multi", False)) {
            picks: list[str] = list(p.get("toggled", []));
            if not picks {
                picks = [chosen_id];
            }
            _close_picker(app);
            if title == "EXPLORER" {
                _insert_into_draft(app, _format_mentions(picks));
            }
            app.dirty = True;
            return;
        }
        _close_picker(app);
        if title == "RESUME SESSION" {
            reply = _resume_session(app, chosen_id);
            if reply {
                _push_turn(app, "tool", reply);
            }
        } elif title == "TASKS" {
            _push_turn(app, "tool", format_tasks_list(load_tasks(os.getcwd())));
        } elif title == "CHECKPOINTS" {
            reply = _restore_checkpoint(app, chosen_id);
            if reply {
                _push_turn(app, "tool", reply);
            }
        } elif title == "SKILLS" {
            _insert_into_draft(app, "/skill:" + chosen_id + " ");
        }
        app.dirty = True;
    }
}

impl _history_up(app: LiveShell) {
    editor_history_prev(app.shell.prompt);
    app.dirty = True;
}

impl _history_down(app: LiveShell) {
    editor_history_next(app.shell.prompt);
    app.dirty = True;
}

impl _tick_cmd(app: LiveShell) {
    if app.cmd_q is None {
        return;
    }
    drained = False;
    while True {
        try {
            item: any = app.cmd_q.get_nowait();
        } except queue.Empty {
            break;
        }
        drained = True;
        name = str(item[1].get("name", "?"));
        out = str(item[1].get("output", ""));
        ok = item[1].get("ok") is True;
        tag = "[ext] /" + name + " -> ";
        for ln in out.split("\n")[:8] {
            _push_turn(app, "tool", tag + ln[:160]);
            tag = "      ";
        }
        if not ok {
            _push_turn(app, "tool", "! [ext] /" + name + " failed");
        }
    }
    if drained {
        app.dirty = True;
    }
}

impl _tick_app(app: LiveShell) {
    _tick_login(app);
    _tick_cmd(app);
    _tick_ui_modal(app);
    if app.phase == "streaming" {
        _tick_stream(app);
    } elif app.phase == "approval" {
        app.spin_i += 1;
        if app.spin_i % 4 == 0 {
            app.dirty = True;
        }
    }
}

impl _handle_key(app: LiveShell, key: str) {
    if key == "ctrl+c" {
        app.running = False;
        return;
    }
    if key == "ctrl+l" {
        app.dirty = True;
        return;
    }
    if app.phase == "approval" {
        if key == "a" or key == "y" or key == "enter" {
            _accept_approval(app);
        } elif key == "r" or key == "n" or key == "escape" {
            _reject_approval(app);
        }
        return;
    }
    if _ui_modal_state(app) is not None {
        _handle_ui_modal_key(app, key);
        return;
    }
    if _picker_state(app) is not None {
        _handle_picker_key(app, key);
        return;
    }
    if app.windows {
        _handle_window_key(app, key);
        return;
    }
    scs = list_extension_shortcuts();
    if key in scs {
        meta: dict[str, any] = scs[key];
        reply = run_extension_shortcut(key);
        if reply {
            _push_turn(app, "tool", reply);
        }
        app.dirty = True;
        return;
    }
    if key == "shift+tab" {
        app.mode = cycle_mode(app.mode);
        set_mode(app.mode);
        app.dirty = True;
        return;
    }
    popup: list[list[str]] | None = _slash_popup_state(app);
    if popup is not None {
        count = len(popup);
        if key == "up" {
            app.slash_sel = (int(app.slash_sel) - 1 + count) % count;
            app.dirty = True;
            return;
        }
        if key == "down" {
            app.slash_sel = (int(app.slash_sel) + 1) % count;
            app.dirty = True;
            return;
        }
        if key == "tab" or key == "enter" {
            (chosen, submit) = _slash_popup_pick(popup, app.shell.prompt.draft, int(app.slash_sel));
            if not (key == "enter" and submit) {
                app.shell.prompt.draft = chosen;
                app.shell.prompt.caret = len(chosen);
                app.shell.prompt.history_index = -1;
                app.slash_dismissed = chosen;
                app.dirty = True;
                return;
            }
        }
        if key == "escape" {
            app.slash_dismissed = app.shell.prompt.draft;
            app.dirty = True;
            return;
        }
    }
    if key == "alt+ctrl+k" {
        _scroll_transcript(app, -(max(1, app.proj.viewport_height) - 1));
        return;
    }
    if key == "alt+ctrl+j" {
        _scroll_transcript(app, max(1, app.proj.viewport_height) - 1);
        return;
    }
    if key == "page_up" {
        _scroll_transcript(app, -(max(1, app.proj.viewport_height) - 1));
        return;
    }
    if key == "page_down" {
        _scroll_transcript(app, max(1, app.proj.viewport_height) - 1);
        return;
    }
    if key == "left" or key == "ctrl+b" {
        editor_move_left(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "right" or key == "ctrl+f" {
        editor_move_right(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "ctrl+a" {
        editor_move_home(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "ctrl+e" {
        editor_move_end(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "alt+b" {
        editor_move_word_left(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "alt+f" {
        editor_move_word_right(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "ctrl+k" {
        editor_kill_to_end(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "ctrl+w" {
        editor_kill_word_left(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "alt+d" {
        editor_kill_word_right(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "alt+backspace" or key == "alt+\x7f" {
        editor_kill_word_left(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "ctrl+y" {
        editor_yank(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "ctrl+t" {
        editor_transpose(app.shell.prompt);
        app.dirty = True;
        return;
    }
    if key == "home" {
        set_follow_tail(app.proj, False);
        app.proj.view.scroll_offset = 0;
        app.dirty = True;
        return;
    }
    if key == "end" {
        set_follow_tail(app.proj, True);
        app.dirty = True;
        return;
    }
    if key == "escape" {
        if app.phase == "streaming" {
            cancel_active_turn();
            app.dirty = True;
            return;
        }
        app.running = False;
        return;
    }
    if key == "up" {
        if app.phase != "streaming" {
            _history_up(app);
        }
        return;
    }
    if key == "ctrl+p" {
        if app.phase != "streaming" {
            _history_up(app);
        }
        return;
    }
    if key == "down" {
        if app.phase != "streaming" {
            _history_down(app);
        }
        return;
    }
    if key == "ctrl+n" {
        if app.phase != "streaming" {
            _history_down(app);
        }
        return;
    }
    if key == "enter" {
        if app.phase == "streaming" {
            return;
        }
        text = app.shell.prompt.draft.strip();
        if not text {
            return;
        }
        shell_submit(app.session, app.shell);
        app.slash_dismissed = "";
        if text.startswith("/") {
            reply = _run_slash(app, text);
            if reply {
                _push_turn(app, "tool", reply);
            }
            app.dirty = True;
            return;
        }
        expanded: str = text;
        try {
            expanded = _expand_quoted_context(os.getcwd(), text);
        } except Exception {
            expanded = text;
        }
        _begin_assistant_reply(app, text, expanded);
        return;
    }
    if key == "backspace" {
        if app.shell.prompt.draft {
            editor_backspace(app.shell.prompt);
            app.shell.prompt.history_index = -1;
            app.dirty = True;
        }
        return;
    }
    if key == "ctrl+u" {
        editor_kill_to_start(app.shell.prompt);
        app.shell.prompt.history_index = -1;
        app.dirty = True;
        return;
    }
    if key == "ctrl+d" {
        if app.shell.prompt.draft {
            editor_delete_forward(app.shell.prompt);
            app.dirty = True;
        } else {
            app.running = False;
        }
        return;
    }
}

impl _handle_host_events(app: LiveShell, events: list[HostEvent]) {
    for event in coalesce_events(events) {
        if isinstance(event, TextEvent) {
            if app.phase == "approval" {
                if event.text in ["a", "y", "r", "n"] {
                    _handle_key(app, event.text);
                }
                continue;
            }
            if _ui_modal_state(app) is not None {
                for ch in event.text {
                    _handle_ui_modal_key(app, ch);
                }
                continue;
            }
            if _picker_state(app) is not None {
                for ch in event.text {
                    _handle_picker_key(app, ch);
                }
                continue;
            }
            if app.windows and app.phase != "approval" {
                for ch in event.text {
                    _handle_window_key(app, ch);
                }
                continue;
            }
            if app.shell.approval is not None {
                if event.text in ["a", "y", "r", "n"] {
                    _handle_key(app, event.text);
                }
                continue;
            }
            if app.phase == "streaming" {
                continue;
            }
            shell_insert_text(app.session, app.shell, event.text);
            app.dirty = True;
        } elif isinstance(event, KeyEvent) {
            _handle_key(app, event.key);
        } elif isinstance(event, PasteEvent) {
            if app.phase == "approval" {
                continue;
            }
            if _ui_modal_state(app) is not None {
                for ch in event.text {
                    _handle_ui_modal_key(app, ch);
                }
                continue;
            }
            if _picker_state(app) is not None {
                for ch in event.text {
                    _handle_picker_key(app, ch);
                }
                continue;
            }
            if app.windows and app.phase != "approval" {
                for ch in event.text {
                    _handle_window_key(app, ch);
                }
                continue;
            }
            if app.shell.approval is None and app.phase != "streaming" {
                shell_insert_text(app.session, app.shell, event.text);
                app.dirty = True;
            }
        }
    }
}
