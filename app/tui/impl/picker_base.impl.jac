impl _open_picker(
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
    win = WindowState(spec=WindowSpec(title="? " + title, width=46), kind="picker", payload=state);
    if not _open_window(app, win) {
        return False;
    }

    app.dirty = True;
    return True;
}

impl _close_picker(app: LiveShell) {
    if _picker_state(app) is None {
        return;
    }
    _close_top_window(app);
}

impl _picker_filtered(p: dict[str, any]) -> tuple[list[str], list[str]] {
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

impl _multi_filtered(p: dict[str, any]) -> tuple[list[str], list[str]] {
    return _picker_filtered(p);
}
