"""E2E: MCP servers and subagents through the real entry and mock model."""

import sys;


def _mcp_cfg(env_fail: bool = False) -> dict[str, any] {
    return {"mcp": {"servers": {"fake": {"command": [sys.executable if not env_fail else "false", fixture_path("fake_mcp.py")]}}}};
}


test "mcp tools are offered on the first request and callable" {
    sb = make_sandbox();
    try {
        write_project_config(sb, _mcp_cfg());
        sb.script([
            {"text": "", "tool_calls": [{"name": "mcp_fake_echo", "args": {"text": "ping"}}]},
            {"text": "mcp said hi"},
        ]);
        r = run_jackal(sb, ["-p", "--mode", "yolo", "use mcp"]);
        assert r.code == 0, sb.explain(r);
        calls = sb.calls();
        assert "mcp_fake_echo" in calls[0]["tools"], sb.explain(r);
        assert "mcp_fake_add" in calls[0]["tools"], sb.explain(r);
        assert calls[1]["last"]["content"] == "echo: ping", sb.explain(r);
        assert r.stdout.strip() == "mcp said hi";
    } finally {
        sb.cleanup();
    }
}


test "a failing mcp server degrades without breaking the turn" {
    sb = make_sandbox();
    try {
        write_project_config(sb, _mcp_cfg(env_fail=True));
        sb.script([{"text": "still works"}]);
        r = run_jackal(sb, ["-p", "q"]);
        assert r.code == 0, sb.explain(r);
        assert r.stdout.strip() == "still works", sb.explain(r);
        for t in sb.calls()[0]["tools"] {
            assert not str(t).startswith("mcp_fake_"), sb.explain(r);
        }
    } finally {
        sb.cleanup();
    }
}


test "repl /mcp reports server status" {
    sb = make_sandbox();
    try {
        write_project_config(sb, _mcp_cfg());
        sb.script([{"text": "warm"}]);
        # One turn first so the attach flow has settled before /mcp.
        r = run_jackal(sb, [], stdin_text="hi\n/mcp\n/exit\n");
        assert r.code == 0, sb.explain(r);
        assert "fake — connected · 2 tools" in r.stdout, sb.explain(r);
    } finally {
        sb.cleanup();
    }
}


test "subagent runs a nested loop and returns its report" {
    sb = make_sandbox({"README.md": "secret word: kumquat\n"});
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "subagent", "args": {"task": "find the secret word in README.md"}}]},
            # nested subagent loop
            {"text": "", "tool_calls": [{"name": "read_file", "args": {"path": "README.md"}}]},
            {"text": "the word is kumquat"},
            # back in the main loop
            {"text": "subagent found kumquat"},
        ]);
        r = run_jackal(sb, ["-p", "--mode", "auto-accept", "delegate it"]);
        assert r.code == 0, sb.explain(r);
        assert r.stdout.strip() == "subagent found kumquat", sb.explain(r);
        calls = sb.calls();
        assert len(calls) == 4, sb.explain(r);
        # Nested call 1 starts fresh: system + task only, and no recursion tool.
        assert calls[1]["messages"] == 2, sb.explain(r);
        assert calls[1]["last"]["content"] == "find the secret word in README.md";
        assert "subagent" not in calls[1]["tools"];
        # The main loop got only the report back.
        assert calls[3]["last"]["role"] == "tool";
        assert calls[3]["last"]["content"] == "the word is kumquat";
    } finally {
        sb.cleanup();
    }
}


test "task tools persist the board across processes" {
    sb = make_sandbox();
    try {
        sb.script([
            {"text": "", "tool_calls": [{"name": "create_task", "args": {"title": "ship it"}}]},
            {"text": "planned"},
        ]);
        r = run_jackal(sb, ["-p", "--mode", "auto-accept", "plan work"]);
        assert r.code == 0, sb.explain(r);
        assert "ship it" in sb.read(".jackal/tasks.json"), sb.explain(r);
    } finally {
        sb.cleanup();
    }
}
