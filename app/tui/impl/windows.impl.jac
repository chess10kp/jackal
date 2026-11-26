impl _open_window(app: LiveShell, win: WindowState, force: bool = False) -> bool {
    if not force
        and app.windows
        and (
            app.windows[len(app.windows) - 1].kind == "picker"
            or app.windows[len(app.windows) - 1].kind == "ui_modal"
        )
    {
        return False;
    }
    if win.refresh is not None {
        try {
            win.refresh(app, win);
        } except Exception {}
    }
    ui_method: str = "";
    if win.kind == "ui_modal" and isinstance(win.payload, dict) {
        ui_method = str(win.payload.get("method", ""));
    }
    inline_choice: bool = win.kind == "picker"
        or (win.kind == "ui_modal" and ui_method == "select");
    if app.shell.approval is None and not inline_choice {
        shell_open_approval(app.session, app.shell);
    }
    app.windows.append(win);
    app.dirty = True;
    return True;
}

impl _close_top_window(app: LiveShell) -> bool {
    if not app.windows {
        return False;
    }
    win = app.windows.pop();
    if not app.windows and app.shell.approval is not None {
        shell_close_approval(app.session, app.shell);
    }
    app.dirty = True;
    return True;
}

impl _handle_window_key(app: LiveShell, key: str) -> bool {
    if not app.windows {
        return False;
    }
    win = app.windows[len(app.windows) - 1];
    if key == "escape" or key == "q" {
        _close_top_window(app);
        return True;
    }
    if (key == "up" or key == "down") and win.selected >= 0 and len(win.rows) > 0 {
        if key == "up" {
            win.selected = max(0, int(win.selected) - 1);
        } else {
            win.selected = min(len(win.rows) - 1, int(win.selected) + 1);
        }
        app.dirty = True;
        return True;
    }
    action = str(win.keys.get(key, ""));
    if action and win.on_action is not None {
        reply = "";
        try {
            reply = str(win.on_action(app, win, action));
        } except Exception as e {
            reply = "window action failed: " + str(e);
        }
        if reply {
            _push_turn(app, "tool", reply);
        }
        if win.refresh is not None {
            try {
                win.refresh(app, win);
            } except Exception {}
        }
        if win.selected >= len(win.rows) {
            win.selected = len(win.rows) - 1;
        }
        app.dirty = True;
        return True;
    }
    return True;
}

impl _window_paint_lines(app: LiveShell) -> list[str] | None {
    if not app.windows {
        return None;
    }
    win = app.windows[len(app.windows) - 1];
    if win.refresh is not None {
        try {
            win.refresh(app, win);
        } except Exception {}
    }
    return window_lines(win);
}

impl _picker_state(app: LiveShell) -> any {
    if app.windows and app.windows[len(app.windows) - 1].kind == "picker" {
        return app.windows[len(app.windows) - 1].payload;
    }
    return None;
}

impl _ui_modal_state(app: LiveShell) -> any {
    if app.windows and app.windows[len(app.windows) - 1].kind == "ui_modal" {
        return app.windows[len(app.windows) - 1].payload;
    }
    return None;
}

impl _approval_state(app: LiveShell) -> any {
    if app.windows and app.windows[len(app.windows) - 1].kind == "approval" {
        return app.windows[len(app.windows) - 1].payload;
    }
    return None;
}
