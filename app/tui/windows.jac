"""Window stack host: lifecycle, key routing and paint bridge for the
tui/window.jac API.

Windows are modal like pickers: the top of the stack owns keys and the
shared overlay node (the ApprovalOverlay UiNode borrowed via
shell_open_approval, the same seam picker_base uses). Pure chrome/viewport
math lives in tui/window.jac; this module touches ui.screen seams and is
covered by e2e rather than annexes.

Precedence mirrors the existing owners: _open_window refuses while a
picker or extension modal is up; a pending tool approval overrides a
window in both paint (overlay.jac) and keys (input.jac gates on
app.phase == "approval") — a blocking approval must never hide behind a
status window."""
import from tui.state { LiveShell }
import from tui.window { WindowState, window_lines }
import from tui.core { _push_turn }
import from ui.screen { shell_open_approval, shell_close_approval }


"""Push a window onto the stack and take over the overlay node.

Returns False (no-op) while a picker or extension modal owns the screen.
Stacking a window on top of a window is allowed (e.g. a confirm over a
status list)."""
def _open_window(app: LiveShell, win: WindowState, force: bool = False) -> bool {
    if not force and app.windows and (
        app.windows[len(app.windows) - 1].kind == "picker"
        or app.windows[len(app.windows) - 1].kind == "ui_modal"
    ) {
        return False;
    }
    if win.refresh is not None {
        try {
            win.refresh(app, win);
        } except Exception {
        }
    }
    if app.shell.approval is None {
        shell_open_approval(app.session, app.shell);
    }
    app.windows.append(win);
    app.dirty = True;
    return True;
}


"""Pop the top window. Releases the overlay node only when the stack
empties."""
def _close_top_window(app: LiveShell) -> bool {
    if not app.windows {
        return False;
    }
    win = app.windows.pop();
    if not app.windows {
        shell_close_approval(app.session, app.shell);
    }
    app.dirty = True;
    return True;
}


"""Route one key to the top window. Consumes EVERY key while a window is
up (windows are modal) except that an active tool approval keeps
precedence — the caller gates on app.phase. Returns True when consumed."""
def _handle_window_key(app: LiveShell, key: str) -> bool {
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
            } except Exception {
            }
        }
        # Keep the cursor honest after a refresh reshuffles rows.
        if win.selected >= len(win.rows) {
            win.selected = len(win.rows) - 1;
        }
        app.dirty = True;
        return True;
    }
    return True;
}


"""Paint rows for the top window (caller resolved precedence). Refreshes
live data first so status windows never show a stale snapshot."""
def _window_paint_lines(app: LiveShell) -> list[str] | None {
    if not app.windows {
        return None;
    }
    win = app.windows[len(app.windows) - 1];
    if win.refresh is not None {
        try {
            win.refresh(app, win);
        } except Exception {
        }
    }
    return window_lines(win);
}

def _picker_state(app: LiveShell) -> any {
    if app.windows and app.windows[len(app.windows) - 1].kind == "picker" {
        return app.windows[len(app.windows) - 1].payload;
    }
    return None;
}

def _ui_modal_state(app: LiveShell) -> any {
    if app.windows and app.windows[len(app.windows) - 1].kind == "ui_modal" {
        return app.windows[len(app.windows) - 1].payload;
    }
    return None;
}

def _approval_state(app: LiveShell) -> any {
    if app.windows and app.windows[len(app.windows) - 1].kind == "approval" {
        return app.windows[len(app.windows) - 1].payload;
    }
    return None;
}
