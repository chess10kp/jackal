"""E2E: the native TUI driven through a real pseudo-terminal."""

import from e2e.harness { make_sandbox, spawn_tui }


test "tui boots, streams a reply, and quits cleanly on esc" {
    sb = make_sandbox();
    tui = None;
    try {
        sb.script([{"text": "hello from the tui mock"}]);
        tui = spawn_tui(sb);
        assert "ready" in tui.screen_text(), tui.screen_text();
        tui.type_text("hi there");
        tui.wait_for("hi there", 10.0);
        tui.press("enter");
        tui.wait_for("hello from the tui mock", 60.0);
        assert sb.calls()[0]["last"]["content"] == "hi there";
        tui.press("esc");
        code = tui.wait_exit(30.0);
        assert code == 0, "exit " + str(code) + "\n" + tui.screen_text();
        # Terminal restored: left the alternate screen and re-showed the cursor.
        raw = tui.raw_output();
        assert "\x1b[?1049l" in raw;
        assert "\x1b[?25h" in raw;
    } finally {
        if tui is not None { tui.close(); }
        sb.cleanup();
    }
}


test "tui approval modal accepts with y" {
    sb = make_sandbox();
    tui = None;
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "write_file", "args": {"path": "t.txt", "content": "tui"}}]},
            {"text": "file written"},
        ]);
        tui = spawn_tui(sb);
        tui.type_text("make t.txt");
        tui.press("enter");
        tui.wait_for("approve", 60.0);
        tui.press("y");
        tui.wait_for("file written", 60.0);
        assert sb.read("t.txt") == "tui";
    } finally {
        if tui is not None { tui.close(); }
        sb.cleanup();
    }
}


test "tui approval modal rejects with n" {
    sb = make_sandbox();
    tui = None;
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "write_file", "args": {"path": "no.txt", "content": "x"}}]},
            {"text": "not written"},
        ]);
        tui = spawn_tui(sb);
        tui.type_text("make no.txt");
        tui.press("enter");
        tui.wait_for("approve", 60.0);
        tui.press("n");
        tui.wait_for("not written", 60.0);
        assert not sb.exists("no.txt");
        assert "denied" in sb.calls()[1]["last"]["content"];
    } finally {
        if tui is not None { tui.close(); }
        sb.cleanup();
    }
}


test "tui slash commands and mode cycling" {
    sb = make_sandbox();
    tui = None;
    try {
        tui = spawn_tui(sb);
        tui.type_text("/help");
        tui.press("enter");
        tui.wait_for("/compact", 20.0);
        tui.press("shift+tab");
        tui.wait_for("AUTO", 10.0);
        tui.type_text("/mode plan");
        tui.press("enter");
        tui.wait_for("PLAN", 10.0);
        assert sb.calls() == [];
    } finally {
        if tui is not None { tui.close(); }
        sb.cleanup();
    }
}
