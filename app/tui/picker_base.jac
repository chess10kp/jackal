"""Shared picker state transitions."""
import from tui.state { LiveShell }
import from tui.window { WindowSpec, WindowState }
import from tui.windows { _open_window, _close_top_window, _picker_state, _ui_modal_state }
"""Open a generic list-picker in the prompt-anchored drop-up (one at a time).
Rows are display labels; ids map 1:1 onto action payloads. When
extra_last_input is set, a trailing "type name…" row flips the picker into
free-text input mode on enter."""
def _open_picker(
    app: LiveShell,
    title: str,
    rows: list[str],
    ids: list[str],
    extra_last_input: bool = False,
    multi: bool = False,
) -> bool {
    if app.windows or _ui_modal_state(app) is not None or app.phase == "approval" {
        return False;
    }
    options = list(rows);
    full_ids = list(ids);
    if extra_last_input {
        options.append("type name…");
        full_ids.append("__type__");
    }
    if not options and title != "LOGIN" {
        return False;
    }
    state: dict[str, any] = {
        "title": title,
        "options": options,
        "ids": full_ids,
        "selected": 0,
        "mode": "select",
        "draft": "",
        "multi": multi,
        "toggled": [],
        "filter": "",
    };
    win = WindowState(
        spec=WindowSpec(title="? " + title, width=46),
        kind="picker",
        payload=state,
    );
    if not _open_window(app, win) {
        return False;
    }

    app.dirty = True;
    return True;
}


"""Dismiss the picker and restore the pre-open status hint."""
def _close_picker(app: LiveShell) {
    if _picker_state(app) is None {
        return;
    }
    _close_top_window(app);
}
"""Picker rows narrowed by type-to-filter text.

Case-insensitive substring match over option labels; empty filter returns
the full lists. Paint and key handling share this helper so the cursor index
always refers to the same visible rows. Pure over its input."""
def _picker_filtered(p: dict[str, any]) -> tuple[list[str], list[str]] {
    options: list[str] = list(p.get("options", []));
    ids: list[str] = list(p.get("ids", []));
    filt: str = str(p.get("filter", "")).strip().lower();
    if not filt {
        return (options, ids);
    }
    vis_options: list[str] = [];
    vis_ids: list[str] = [];
    for i in range(len(options)) {
        if filt in str(options[i]).lower() {
            vis_options.append(options[i]);
            vis_ids.append(str(ids[i]) if i < len(ids) else "");
        }
    }
    return (vis_options, vis_ids);
}


def _multi_filtered(p: dict[str, any]) -> tuple[list[str], list[str]] {
    return _picker_filtered(p);
}
