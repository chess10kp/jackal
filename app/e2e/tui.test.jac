"""E2E: the native TUI driven through a real pseudo-terminal."""



test "tui boots, streams a reply, and quits cleanly on esc" {
    sb = make_sandbox();
    tui: TuiSession | None = None;
    try {
        sb.script([{"text": "hello from the tui mock"}]);
        tui = spawn_tui(sb);
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
    tui: TuiSession | None = None;
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
    tui: TuiSession | None = None;
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
    tui: TuiSession | None = None;
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

test "tui streams a 20 KB answer without stalling" {
    sb = make_sandbox();
    tui: TuiSession | None = None;
    try {
        tail = "TAIL-MARKER-9x4";
        body = "stream word " * 1600 + "\n" + tail;
        sb.script([{"text": body}]);
        tui = spawn_tui(sb);
        tui.type_text("long answer please");
        tui.press("enter");
        # 200 deltas arrive through the real PTY; the UI must keep draining
        # (batched rewrites) and end with the reply tail on screen.
        tui.wait_for(tail, 90.0);
        tui.press("esc");
        code = tui.wait_exit(30.0);
        assert code == 0, "exit " + str(code) + "\n" + tui.screen_text();
    } finally {
        if tui is not None { tui.close(); }
        sb.cleanup();
    }
}

test "tui previews long tool results at six lines with a more-lines footer" {
    lines: list[str] = [];
    for i in range(1, 11) {
        lines.append(f"fixture line {i}");
    }
    sb = make_sandbox(files={"big.txt": "\n".join(lines) + "\n"});
    tui: TuiSession | None = None;
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "read_file", "args": {"path": "big.txt"}}]},
            {"text": "done reading"},
        ]);
        tui = spawn_tui(sb);
        tui.type_text("read big.txt");
        tui.press("enter");
        # read_file is read-only: auto-approved in normal mode (no modal).
        tui.wait_for("... (4 more lines)", 60.0);
        tui.wait_for("done reading", 60.0);
        tui.wait_for("fixture line 1", 10.0);
        screen = tui.screen_text();
        # Display truncates: the seventh line never renders.
        assert "fixture line 7" not in screen, screen;
        # Display-only: the full result still reached the model (request 2's
        # last message is the untruncated tool result).
        calls = sb.calls();
        assert len(calls) >= 2, str(calls)[:2000];
        assert "fixture line 7" in calls[1]["last"]["content"], str(calls[1])[:2000];
        tui.press("esc");
        code = tui.wait_exit(30.0);
        assert code == 0, "exit " + str(code) + "\n" + tui.screen_text();
    } finally {
        if tui is not None { tui.close(); }
        sb.cleanup();
    }
}

test "tui mcp window opens, closes, and restart feedback flows" {
    sb = make_sandbox();
    tui: TuiSession | None = None;
    try {
        tui = spawn_tui(sb);
        # No .jackal config in the sandbox: the window shows the empty state.
        tui.type_text("/mcp");
        tui.press("enter");
        tui.wait_for("MCP STATUS", 20.0);
        tui.wait_for("no mcp servers configured", 10.0);
        # esc closes the window (does not quit the app): both markers vanish.
        tui.press("esc");
        tui.wait_gone("MCP STATUS", 20.0);
        tui.wait_gone("no mcp servers configured", 10.0);
        # /mcp restart NAME goes through mcp_restart without a window.
        tui.type_text("/mcp restart ghost");
        tui.press("enter");
        tui.wait_for("unknown mcp server: ghost", 20.0);
        tui.press("esc");
        code = tui.wait_exit(30.0);
        assert code == 0, "exit " + str(code) + "\n" + tui.screen_text();
    } finally {
        if tui is not None { tui.close(); }
        sb.cleanup();
    }
}

test "tui login api-key input accepts a bracketed paste" {
    sb = make_sandbox();
    tui: TuiSession | None = None;
    try {
        tui = spawn_tui(sb);
        # /login -> provider picker (first row: openrouter, an api_key route)
        # -> key input overlay.
        tui.type_text("/login");
        tui.press("enter");
        tui.wait_for("LOGIN", 30.0);
        tui.press("enter");
        tui.wait_for("paste API key", 15.0);
        # Exactly what a terminal sends on ctrl+shift+v. Regression: the
        # PasteEvent branch required app.picker is None and dropped pastes
        # while the key input overlay was open.
        key: str = "sk-e2e-paste-1234567890";
        tui.send("\x1b[200~" + key + "\x1b[201~");
        tui.wait_for("*" * len(key), 10.0);
        tui.press("enter");
        tui.wait_for("logged in to openrouter", 15.0);
        # The decisive assertion: the pasted bytes landed in auth.json.
        auth_path: str = os.path.join(sb.agent_dir, "auth.json");
        fh: any = open(auth_path, "r", encoding="utf-8");
        stored: str = fh.read();
        fh.close();
        assert key in stored, stored;
    } finally {
        if tui is not None { tui.close(); }
        sb.cleanup();
    }
}
