"""E2E: the --json JSONL protocol used by UI clients."""



test "jsonl session lifecycle and a turn" {
    sb = make_sandbox();
    try {
        sb.script([{"text": "pong"}]);
        r = run_jackal(sb, ["--json"], stdin_text=jsonl("user", "ping") + jsonl("command", "/exit"));
        assert r.code == 0, r.describe();
        types = r.event_types();
        assert types[0] == "session_ready", r.describe();
        assert "chunk" in types and "turn_end" in types, r.describe();
        assert types[-1] == "session_end", r.describe();
        contents: list[str] = [];
        for e in r.events() {
            if e.get("type") == "message" { contents.append(str(e.get("content"))); }
        }
        assert contents == ["pong"], r.describe();
    } finally {
        sb.cleanup();
    }
}


test "jsonl approval round-trip gates a write" {
    sb = make_sandbox();
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "write_file", "args": {"path": "a.txt", "content": "A"}}]},
            {"text": "wrote it"},
            {"text": "", "tool_calls": [{"name": "write_file", "args": {"path": "b.txt", "content": "B"}}]},
            {"text": "skipped"},
        ]);
        stdin = (
            jsonl("user", "write a") + jsonl("approval", "", {"approved": True})
            + jsonl("user", "write b") + jsonl("approval", "", {"approved": False})
            + jsonl("command", "/exit")
        );
        r = run_jackal(sb, ["--json"], stdin_text=stdin);
        assert r.code == 0, r.describe();
        assert r.event_types().count("approval_request") == 2, r.describe();
        assert sb.read("a.txt") == "A", r.describe();
        assert not sb.exists("b.txt"), r.describe();
    } finally {
        sb.cleanup();
    }
}


test "jsonl rejects malformed requests without dying" {
    sb = make_sandbox();
    try {
        r = run_jackal(sb, ["--json"], stdin_text="not json\n" + jsonl("command", "/mode") + jsonl("command", "/exit"));
        assert r.code == 0, r.describe();
        saw_bad: bool = False;
        saw_mode: bool = False;
        for e in r.events() {
            if e.get("type") == "error" and "bad json" in str(e.get("message")) { saw_bad = True; }
            if e.get("type") == "info" and "mode: normal" in str(e.get("text")) { saw_mode = True; }
        }
        assert saw_bad, r.describe();
        assert saw_mode, r.describe();
    } finally {
        sb.cleanup();
    }
}
