impl probe_handle_key(app: KeyProbeShell, key: str) {
    if key == "ctrl+c" {
        app.running = False;
        return;
    }
    if app.ui_modal is not None {
        app.ui_modal = key;
        return;
    }
    if app.approval is not None {
        if key in ["a", "y", "enter"] or key in ["r", "n", "escape"] {
            return;
        }
        return;
    }
    scs = list_extension_shortcuts();
    if key in scs {
        meta: dict[str, any] = scs[key];
        desc = str(meta.get("description", "") or "");
        app.status_hint = "shortcut " + key + (" — " + desc if desc else "");
        reply = run_extension_shortcut(key);
        if reply {
            app.tool_replies.append(reply);
        }
        app.dirty = True;
        return;
    }
    if key == "escape" {
        if app.phase == "streaming" {
            app.status_hint = "aborting…";
            app.dirty = True;
            return;
        }
        app.running = False;
        return;
    }
}

impl make_key_probe(bindings: list[tuple[str, str]]) -> tuple[KeyProbeShell, any, list[str]] {
    fired: list[str] = [];

    def _make_handler(result: str) -> any {
        def _handler(ctx: any) -> any {
            fired.append("hit");
            return result;
        }
        return _handler;
    }

    bridge = create_bridge("s-keybinding-probe");
    for binding in bindings {
        key: str = binding[0];
        result: str = binding[1];
        register_fake_shortcut(bridge, key, _make_handler(result), description="Probe " + key);
    }
    plugins.bridge = bridge;
    return (KeyProbeShell(), bridge, fired);
}

impl drop_key_probe(bridge: any) {
    plugins.bridge = None;
    dispose_bridge(bridge);
}
