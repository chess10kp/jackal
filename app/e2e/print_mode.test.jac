"""E2E: one-shot print mode (`jackal -p`) against the scripted mock model."""


import json;


test "print mode answers and exits 0" {
    sb = make_sandbox();
    try {
        sb.script([{"text": "hello from the mock"}]);
        r = run_jackal(sb, ["-p", "say hi"]);
        assert r.code == 0, sb.explain(r);
        assert r.stdout.strip() == "hello from the mock", sb.explain(r);
        calls = sb.calls();
        assert len(calls) == 1, sb.explain(r);
        assert calls[0]["last"]["content"] == "say hi";
        assert "read_file" in calls[0]["tools"];
    } finally {
        sb.cleanup();
    }
}


test "print mode reads the prompt from stdin" {
    sb = make_sandbox();
    try {
        r = run_jackal(sb, ["-p", "summarize"], stdin_text="file body");
        assert r.code == 0, sb.explain(r);
        # Unscripted mock echoes the last user message.
        assert "summarize" in r.stdout and "file body" in r.stdout, sb.explain(r);
    } finally {
        sb.cleanup();
    }
}


test "tool loop edits a file in yolo mode" {
    sb = make_sandbox({"notes.txt": "alpha\n"});
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "read_file", "args": {"path": "notes.txt"}}]},
            {"text": "", "tool_calls": [{"name": "edit_file", "args": {"path": "notes.txt", "old_text": "alpha", "new_text": "beta"}}]},
            {"text": "done"},
        ]);
        r = run_jackal(sb, ["-p", "--mode", "yolo", "rename alpha"]);
        assert r.code == 0, sb.explain(r);
        assert sb.read("notes.txt") == "beta\n", sb.explain(r);
        calls = sb.calls();
        assert len(calls) == 3, sb.explain(r);
        # The model saw the read_file result before editing.
        assert calls[1]["last"]["role"] == "tool";
        assert "alpha" in calls[1]["last"]["content"];
    } finally {
        sb.cleanup();
    }
}


test "normal mode refuses confirm-gated tools without a prompt" {
    sb = make_sandbox({"keep.txt": "original\n"});
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "write_file", "args": {"path": "keep.txt", "content": "clobbered"}}]},
            {"text": "could not write"},
        ]);
        r = run_jackal(sb, ["-p", "overwrite it"]);
        assert r.code == 0, sb.explain(r);
        assert sb.read("keep.txt") == "original\n", sb.explain(r);
        calls = sb.calls();
        assert "needs approval" in calls[1]["last"]["content"], sb.explain(r);
    } finally {
        sb.cleanup();
    }
}


test "plan mode blocks writes" {
    sb = make_sandbox();
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "write_file", "args": {"path": "new.txt", "content": "x"}}]},
            {"text": "planned"},
        ]);
        r = run_jackal(sb, ["-p", "--mode", "plan", "make a file"]);
        assert r.code == 0, sb.explain(r);
        assert not sb.exists("new.txt"), sb.explain(r);
    } finally {
        sb.cleanup();
    }
}


test "json output reports result metadata" {
    sb = make_sandbox();
    try {
        sb.script([{"text": "structured"}]);
        r = run_jackal(sb, ["-p", "--output-format", "json", "q"]);
        assert r.code == 0, sb.explain(r);
        evs = r.events();
        assert len(evs) == 1, sb.explain(r);
        res = evs[0];
        assert res["type"] == "result";
        assert res["result"] == "structured";
        assert res["is_error"] == False;
        assert res["model"] == "mock";
        assert res["session_id"];
    } finally {
        sb.cleanup();
    }
}


test "stream-json emits chunks then a result" {
    sb = make_sandbox();
    try {
        sb.script([{"text": "streamed text"}]);
        r = run_jackal(sb, ["-p", "--output-format", "stream-json", "q"]);
        assert r.code == 0, sb.explain(r);
        types = r.event_types();
        assert "chunk" in types, sb.explain(r);
        assert types[-1] == "result", sb.explain(r);
    } finally {
        sb.cleanup();
    }
}


test "provider error exits 1" {
    sb = make_sandbox();
    try {
        sb.script([{"error": "HTTP 400: bad request"}]);
        r = run_jackal(sb, ["-p", "--output-format", "json", "q"]);
        assert r.code == 1, sb.explain(r);
        res = r.events()[-1];
        assert res["is_error"] == True;
        assert "HTTP 400" in " ".join(res["errors"]);
    } finally {
        sb.cleanup();
    }
}


test "bad flags exit 2 with usage" {
    sb = make_sandbox();
    try {
        r = run_jackal(sb, ["--nope"]);
        assert r.code == 2, sb.explain(r);
        assert "unknown option" in r.stderr and "usage:" in r.stderr, sb.explain(r);
        assert sb.calls() == [];
    } finally {
        sb.cleanup();
    }
}


test "continue resumes the previous session transcript" {
    sb = make_sandbox();
    try {
        sb.script([{"text": "first answer"}, {"text": "second answer"}]);
        r1 = run_jackal(sb, ["-p", "remember 42"]);
        assert r1.code == 0, sb.explain(r1);
        r2 = run_jackal(sb, ["-p", "-c", "what number?"]);
        assert r2.code == 0, sb.explain(r2);
        calls = sb.calls();
        # Second process sent system + first exchange + new prompt.
        assert calls[-1]["messages"] >= 4, sb.explain(r2);
    } finally {
        sb.cleanup();
    }
}
