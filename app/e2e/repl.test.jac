"""E2E: the line REPL frontend driven over piped stdin."""



test "repl runs a turn and slash commands then exits" {
    sb = make_sandbox();
    try {
        sb.script([{"text": "repl answer"}]);
        r = run_jackal(sb, [], stdin_text="hello\n/mode yolo\n/sessions\n/exit\n");
        assert r.code == 0, r.describe();
        assert "repl answer" in r.stdout, r.describe();
        assert "mode -> yolo" in r.stdout, r.describe();
        assert "saved sessions:" in r.stdout, r.describe();
        assert "bye." in r.stdout, r.describe();
    } finally {
        sb.cleanup();
    }
}


test "repl approval prompt accepts y" {
    sb = make_sandbox();
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "write_file", "args": {"path": "y.txt", "content": "yes"}}]},
            {"text": "ok"},
        ]);
        r = run_jackal(sb, [], stdin_text="write y\ny\n/exit\n");
        assert r.code == 0, r.describe();
        assert sb.read("y.txt") == "yes", r.describe();
    } finally {
        sb.cleanup();
    }
}


test "help and version flags" {
    sb = make_sandbox();
    try {
        h = run_jackal(sb, ["--help"]);
        assert h.code == 0 and "usage: jackal" in h.stdout, h.describe();
        v = run_jackal(sb, ["--version"]);
        assert v.code == 0 and v.stdout.startswith("jackal "), v.describe();
    } finally {
        sb.cleanup();
    }
}
