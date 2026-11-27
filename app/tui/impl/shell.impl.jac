impl create_live_shell(term: Terminal | None = None) -> LiveShell {
    host: Terminal = ProcessTerminal();
    cols: int = 80;
    rows: int = 24;
    if term is None {
        (cols, rows) = read_terminal_size(80, 24);
        host.columns = cols;
        host.rows = rows;
    } else {
        host = term;
        (cols, rows) = term.size();
    }
    handle = create_session();
    session = handle.session;
    shell = build_main_shell(session);
    install_shell_contracts(session, shell, "live.transcript");
    proj = bind_transcript(
        shell.transcript, "live.transcript", width=max(12, cols - 2), height=max(4, rows - 5)
    );
    set_follow_tail(proj, True);
    renderer = create_renderer(cols, rows);
    app = LiveShell(
        session=session,
        shell=shell,
        proj=proj,
        renderer=renderer,
        term=host,
        normalizer=InputNormalizer(),
        columns=cols,
        rows=rows,
        mode=get_mode(),
    );
    _install_layout(app);
    return app;
}

impl boot_tui(term: Terminal | None = None) -> LiveShell {
    requested_mode: str = os.environ.get("JACKAL_MODE", "");
    if requested_mode {
        set_mode(requested_mode);
    }
    try {
        session_boot(interactive_ui=True);
    } except Exception {}
    _hydrate_auth_environment();
    app = create_live_shell(term);
    app.cmd_q = queue.Queue();
    app.term.start();
    app.term.set_title("Jackal — " + get_model());
    app.dirty = True;
    _render(app);
    try {
        warm_model_catalog();
    } except Exception {}
    return app;
}

impl tui_step(app: LiveShell, poll_timeout_s: float = 0.04) -> bool {
    (cols, rows) = app.term.size();
    if cols != app.columns or rows != app.rows {
        _apply_resize(app, cols, rows);
    }
    raw = app.term.poll_input(poll_timeout_s);
    if app.term.eof {
        app.running = False;
        return False;
    }
    if raw {
        events = app.normalizer.feed(raw);
        _handle_host_events(app, events);
    } elif app.normalizer.buffer == "\x1b" {
        events = app.normalizer.flush_buffer();
        _handle_host_events(app, events);
    }
    _tick_app(app);
    for notice in drain_mcp_notices() {
        _push_turn(app, "tool", notice);
        app.dirty = True;
    }
    _render(app);
    return app.running;
}

impl shutdown_tui(app: LiveShell) {
    try {
        app.term.hide_cursor();
        app.term.stop();
    } except Exception {}
    dispose_session(app.session);
}

impl run_tui {
    try {
        app = boot_tui();
    } except ValueError as e {
        print("jackal: " + str(e));
        raise SystemExit(2);
    }
    try {
        while tui_step(app, 0.04) {}
    } except KeyboardInterrupt {
        app.running = False;
    } finally {
        shutdown_tui(app);
    }
}
