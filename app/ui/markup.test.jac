"""Unit 12 acceptance: markup lowering, errors, and print-generated mode.

Companion scope provides markup APIs. This annex stays inside `ui.markup`'s
native unit (hard pin), so it must not import the server-placed screen/runtime
modules — the cross-context cases live in `ui/screen.test.jac` instead.
"""

import from ui.model {
    MainScreen,
    ordered_child_keys,
}


test "default_shell_registry has Jackal shell tags" {
    reg = default_shell_registry();
    assert "MainScreen" in reg.tags;
    assert "TranscriptView" in reg.tags;
    assert "Prompt" in reg.tags;
    assert "ApprovalOverlay" in reg.tags;
}


test "register_tag rejects empty name" {
    reg = create_tag_registry();
    failed = False;
    try {
        register_tag(reg, "", MainScreen);
    } except ValueError {
        failed = True;
    }
    assert failed;
}


test "unknown tag is a lowering error" {
    source = "<Nope key=\"x\" />";
    result = lower_markup(source, default_shell_registry());
    assert result.graph_root is None;
    assert len(result.errors) >= 1;
    msg = result.errors[0].message;
    assert ("Nope" in msg) or ("unknown" in msg.lower());
}


test "unknown property is a lowering error" {
    source = "<Prompt key=\"prompt\" not_a_real_prop=\"1\" />";
    result = lower_markup(source, default_shell_registry());
    assert len(result.errors) >= 1;
}


test "shell markup lowers to MainScreen with expected children" {
    source = """
    <MainScreen key="main">
      <Header key="header" title="Jackal" />
      <TranscriptView key="transcript" />
      <Status key="status" phase="ready" />
      <Prompt key="prompt" />
    </MainScreen>
    """;
    result = lower_markup(source, default_shell_registry());
    assert result.errors == [];
    assert result.graph_root is not None;
    screen = result.graph_root;
    assert isinstance(screen, MainScreen);
    keys = ordered_child_keys(screen);
    assert keys == ["header", "transcript", "status", "prompt"];
}


test "print_generated emits direct-construction Jac" {
    source = """
    <MainScreen key="main">
      <Prompt key="prompt" />
    </MainScreen>
    """;
    text = print_generated(source, default_shell_registry());
    assert "MainScreen" in text;
    assert "Prompt" in text;
    assert ("append_child" in text) or ("Child" in text);
}
