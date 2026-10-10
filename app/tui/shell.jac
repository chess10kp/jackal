"""Jackal TUI coordinator. Behavior lives in responsibility modules."""

import sys;
import os;
import queue;
import from tui.state { LiveShell }
import from tui.picker_actions { _hydrate_auth_environment }
import from tui.core { _push_turn, _install_layout }
import from tui.overlay { _render }
import from tui.runtime { _apply_resize }
import from tui.input { _tick_app, _handle_host_events }
import from agent.session { session_boot, get_model, set_mode, get_mode, drain_mcp_notices }
import from agent.llm { warm_model_catalog }
import from ui.runtime { create_session, dispose_session }
import from ui.screen { build_main_shell, install_shell_contracts }
import from ui.transcript { bind_transcript, set_follow_tail }
import from ui.renderer { create_renderer }
import from ui.terminal { Terminal, ProcessTerminal, read_terminal_size }
import from ui.input { InputNormalizer }
import from ui.progress_bar { ProgressBar }

"""Build the LiveShell. `term` defaults to the process TTY; tests pass an
EmulatedTerminal (ui/emulated_terminal.jac) and drive the same shell."""
def create_live_shell(term: Terminal | None = None) -> LiveShell {
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
        shell.transcript,
        "live.transcript",
        width=max(12, cols - 2),
        height=max(4, rows - 7),
    );
    set_follow_tail(proj, True);
    renderer = create_renderer(cols, rows);
    progress = ProgressBar(key="live_progress", value=0.0);
    app = LiveShell(
        session=session,
        shell=shell,
        proj=proj,
        renderer=renderer,
        term=host,
        normalizer=InputNormalizer(),
        progress=progress,
        columns=cols,
        rows=rows,
        mode=get_mode(),
    );
    _install_layout(app);
    _push_turn(
        app,
        "system",
        "session attached · detached graph · retained paint\n"
        + "say something — watch the stream, then the approval modal",
    );
    return app;
}


"""Boot session + shell on `term` and paint the first frame. Raises
ValueError for an invalid JACKAL_MODE."""
def boot_tui(term: Terminal | None = None) -> LiveShell {
    requested_mode: str = os.environ.get("JACKAL_MODE", "");
    if requested_mode {
        set_mode(requested_mode);
    }
    # Extensions load per .jackal/extensions.json (parallel sidecar when declared).
    try {
        session_boot(interactive_ui=True);
    } except Exception {
    }
    _hydrate_auth_environment();
    # fx-style catalog preload: /models endpoints refresh in background
    # flows so the picker serves live lists without blocking first paint.
    try {
        warm_model_catalog();
    } except Exception {
    }
    app = create_live_shell(term);
    app.cmd_q = queue.Queue();
    app.term.start();
    app.term.set_title("Jackal — " + get_model());
    app.dirty = True;
    _render(app);
    return app;
}


"""One host-loop iteration: resize check, input, tick, notices, paint.
Returns False once the shell should exit."""
def tui_step(app: LiveShell, poll_timeout_s: float = 0.04) -> bool {
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


"""Restore the terminal and dispose the UI session (idempotent)."""
def shutdown_tui(app: LiveShell) {
    try {
        app.term.hide_cursor();
        app.term.stop();
    } except Exception {
    }
    dispose_session(app.session);
}


def run_tui() {
    try {
        app = boot_tui();
    } except ValueError as e {
        print("jackal: " + str(e));
        raise SystemExit(2);
    }
    try {
        while tui_step(app, 0.04) {
        }
    } except KeyboardInterrupt {
        app.running = False;
    } finally {
        shutdown_tui(app);
    }
}


with entry:__main__ {
    if not sys.stdin.isatty() or not sys.stdout.isatty() {
        print("jackal tui needs a real TTY.");
        raise SystemExit(1);
    }
    run_tui();
}
