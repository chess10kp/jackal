test "extension shortcut shadows navigation key and carries result" {
    (app, bridge, fired) = make_key_probe([("up", "probe result")]);
    try {
        scs = list_extension_shortcuts();
        assert list(scs.keys()) == ["up"];
        assert scs["up"]["description"] == "Probe up";
        assert scs["up"]["extension_id"] == "fake.shortcuts";
        probe_handle_key(app, "up");
        assert len(fired) == 1;
        assert app.status_hint == "shortcut up — Probe up";
        assert app.dirty is True;
        assert app.running is True;
        assert app.tool_replies == ["probe result"];
    } finally {
        drop_key_probe(bridge);
    }
}

test "ctrl+c keeps precedence over a registered shortcut" {
    (app, bridge, fired) = make_key_probe([("ctrl+c", "never")]);
    try {
        assert len(list(list_extension_shortcuts().keys())) == 1;
        probe_handle_key(app, "ctrl+c");
        assert app.running is False;
        assert len(fired) == 0;
        assert app.status_hint == "";
    } finally {
        drop_key_probe(bridge);
    }
}

test "pending approval swallows shortcut keys" {
    (app, bridge, fired) = make_key_probe([("q", "never")]);
    try {
        app.approval = {"tool": "run_command"};
        probe_handle_key(app, "q");
        assert len(fired) == 0;
        assert app.status_hint == "";
        assert app.running is True;
    } finally {
        drop_key_probe(bridge);
    }
}

test "extension-UI modal swallows keys ahead of shortcuts" {
    (app, bridge, fired) = make_key_probe([("x", "never")]);
    try {
        app.ui_modal = True;
        probe_handle_key(app, "x");
        assert app.ui_modal == "x";
        assert len(fired) == 0;
    } finally {
        drop_key_probe(bridge);
    }
}

test "escape aborts streaming and quits an idle shell when unregistered" {
    (app, bridge, fired) = make_key_probe([("up", "unused")]);
    try {
        app.phase = "streaming";
        probe_handle_key(app, "escape");
        assert app.running is True;
        assert app.status_hint == "aborting…";
        assert app.dirty is True;

        app.phase = "ready";
        probe_handle_key(app, "escape");
        assert app.running is False;
    } finally {
        drop_key_probe(bridge);
    }
}
