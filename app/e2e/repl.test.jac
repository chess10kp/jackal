"""E2E: the line REPL frontend driven over piped stdin."""



test "repl runs a turn and slash commands then exits" {
    sb = make_sandbox();
    try {
        sb.script([{"text": "repl answer"}]);
        r = run_jackal(sb, [], stdin_text="hello\n/mode yolo\n/sessions\n/exit\n");
        assert r.code == 0, sb.explain(r);
        assert "repl answer" in r.stdout, sb.explain(r);
        assert "mode -> yolo" in r.stdout, sb.explain(r);
        assert "saved sessions:" in r.stdout, sb.explain(r);
        assert "bye." in r.stdout, sb.explain(r);
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
        assert r.code == 0, sb.explain(r);
        assert sb.read("y.txt") == "yes", sb.explain(r);
    } finally {
        sb.cleanup();
    }
}


test "help and version flags" {
    sb = make_sandbox();
    try {
        h = run_jackal(sb, ["--help"]);
        assert h.code == 0 and "usage: jackal" in h.stdout, sb.explain(h);
        v = run_jackal(sb, ["--version"]);
        assert v.code == 0 and v.stdout.startswith("jackal "), sb.explain(v);
    } finally {
        sb.cleanup();
    }
}
