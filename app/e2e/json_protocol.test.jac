"""E2E: the --json JSONL protocol used by UI clients."""

import from e2e.harness { make_sandbox, run_jackal, jsonl }


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
        msgs = [e for e in r.events() if e.get("type") == "message"];
        assert msgs and msgs[0]["content"] == "pong", r.describe();
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
        evs = r.events();
        assert any([e.get("type") == "error" and "bad json" in str(e.get("message")) for e in evs]), r.describe();
        assert any([e.get("type") == "info" and "mode: normal" in str(e.get("text")) for e in evs]), r.describe();
    } finally {
        sb.cleanup();
    }
}
