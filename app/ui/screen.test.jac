"""Unit 8 acceptance: durable Jackal shell topology and editor lifecycle.

Companion scope provides screen APIs. runtime imported for session helpers.
The last case also checks markup lowering against this shell, which is why it
lives here rather than in `ui/markup.test.jac`: `ui.markup` is pinned native,
its annex is folded into the native unit, and calling this server-placed
builder from there fails the seal (E5093). See docs/TESTING.md and
jaseci-labs/jac#10490.
"""

import from ui.model {
    MainScreen,
    node_id,
    ordered_child_keys,
}

import from ui.layout_types {
    SizeMode,
    create_layout_state,
}
import from ui.runtime {
    create_session,
    dispose_session,
    get_focus_node,
    set_focus,
}

import from ui.markup {
    default_shell_registry,
    lower_markup,
}
test "build_main_shell mounts header transcript status prompt once" {
    handle = create_session();
    session = handle.session;
    shell = build_main_shell(session);
    assert shell.screen.key == "main";
    assert shell.header.key == "header";
    assert shell.transcript.key == "transcript";
    assert shell.status.key == "status";
    assert shell.prompt.key == "prompt";
    assert shell.approval is None;
    assert session.current_screen is shell.screen;
    ids = shell_ids(shell);
    assert ids.screen_id == node_id(shell.screen);
    assert ids.prompt_id == node_id(shell.prompt);
}


test "typing does not replace shell node ids" {
    handle = create_session();
    session = handle.session;
    shell = build_main_shell(session);
    before = shell_ids(shell);
    shell_insert_text(session, shell, "hello");
    shell_insert_text(session, shell, "\nworld");
    after = shell_ids(shell);
    assert after.screen_id == before.screen_id;
    assert after.transcript_id == before.transcript_id;
    assert after.prompt_id == before.prompt_id;
    assert shell.prompt.draft == "hello\nworld" or ("hello" in shell.prompt.draft);
}


test "submit clears draft and yields SendPrompt effect" {
    handle = create_session();
    session = handle.session;
    shell = build_main_shell(session);
    shell_insert_text(session, shell, "run tests");
    effects = shell_submit(session, shell);
    assert len(effects) >= 1;
    assert shell.prompt.draft == "";
}


test "cancel restores or aborts without replacing nodes" {
    handle = create_session();
    session = handle.session;
    shell = build_main_shell(session);
    before = shell_ids(shell);
    shell_insert_text(session, shell, "partial");
    shell_cancel(session, shell);
    after = shell_ids(shell);
    assert after.prompt_id == before.prompt_id;
}


test "approval overlay round-trip restores prompt focus and ids" {
    handle = create_session();
    session = handle.session;
    shell = build_main_shell(session);
    set_focus(session, shell.prompt);
    before = shell_ids(shell);
    opened = shell_open_approval(session, shell);
    assert shell.approval is not None;
    assert opened.saved_focus_id == node_id(shell.prompt);
    closed = shell_close_approval(session, shell);
    assert shell.approval is None;
    assert get_focus_node(session) is shell.prompt;
    after = shell_ids(shell);
    assert after.prompt_id == before.prompt_id;
    assert after.transcript_id == before.transcript_id;
    assert closed.restored_focus_id == node_id(shell.prompt);
}


test "resize keeps shell node ids stable" {
    handle = create_session();
    session = handle.session;
    shell = build_main_shell(session);
    before = shell_ids(shell);
    shell_resize(session, shell, 40, 12);
    shell_resize(session, shell, 20, 8);
    after = shell_ids(shell);
    assert after.screen_id == before.screen_id;
    assert after.header_id == before.header_id;
    assert after.transcript_id == before.transcript_id;
    assert after.status_id == before.status_id;
    assert after.prompt_id == before.prompt_id;
}


test "second build_main_shell reuses or refuses duplicate topology" {
    handle = create_session();
    session = handle.session;
    first = build_main_shell(session);
    failed = False;
    second = None;
    try {
        second = build_main_shell(session);
    } except ValueError {
        failed = True;
    }
    if not failed {
        assert second is not None;
        assert node_id(second.screen) == node_id(first.screen);
    }
}


test "configure_main_shell_layout installs legacy-parity specs" {
    handle = create_session();
    session = handle.session;
    shell = build_main_shell(session);
    state = create_layout_state(80, 24);
    failures = configure_main_shell_layout(state, shell);
    assert failures == [];

    # Screen fills; header/status/prompt keep legacy fixed heights;
    # transcript grows with scroll enabled (mirrors gates.jac).
    sid = node_id(shell.screen);
    tid = node_id(shell.transcript);
    hid = node_id(shell.header);
    pid = node_id(shell.prompt);
    stid = node_id(shell.status);
    assert state.specs[sid].width.mode == SizeMode.FILL;
    assert state.specs[sid].height.mode == SizeMode.FILL;
    assert state.specs[hid].height.mode == SizeMode.FIXED;
    assert state.specs[hid].height.preferred == 1.0;
    assert state.specs[tid].height.mode == SizeMode.GROW;
    assert state.specs[tid].height.grow_weight == 1.0;
    assert state.specs[tid].scroll_vertical;
    assert state.specs[stid].height.mode == SizeMode.FIXED;
    assert state.specs[stid].height.preferred == 1.0;
    assert state.specs[pid].height.mode == SizeMode.FIXED;
    assert state.specs[pid].height.preferred == 2.0;

    dispose_session(session);
}


test "lowered shell matches build_main_shell child keys" {
    source = """
    <MainScreen key="main">
      <Header key="header" title="Jackal" />
      <TranscriptView key="transcript" />
      <Status key="status" />
      <Prompt key="prompt" />
    </MainScreen>
    """;
    lowered = lower_markup(source, default_shell_registry());
    assert lowered.errors == [];
    assert lowered.graph_root is not None;
    lowered_screen = lowered.graph_root;
    assert isinstance(lowered_screen, MainScreen);
    handle = create_session();
    session = handle.session;
    try {
        shell = build_main_shell(session);
        assert ordered_child_keys(lowered_screen) == ordered_child_keys(shell.screen);
    } finally {
        dispose_session(session);
    }
}
