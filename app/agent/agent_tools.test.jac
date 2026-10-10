"""Task-board and subagent tool tests (merged with agent/agent_tools.jac)."""

import tempfile;
import shutil;
import from .registry { create_registry, register_native }


def _noop(args: dict[str, any]) -> str {
    return "";
}


test "task tools round-trip through the board" {
    tmp_dir = tempfile.mkdtemp(prefix="jackal-agent-tools-");
    saved = plugins.cwd;
    plugins.cwd = tmp_dir;
    try {
        assert _create_task_tool({"title": ""}).startswith("ERROR");
        out = _create_task_tool({"title": "write tests"});
        assert out.startswith("created [");
        tid = out[len("created ["):out.index("]")];
        board = _update_task_tool({"id": tid, "status": "in_progress"});
        assert "1 in progress" in board;
        assert _update_task_tool({"id": tid, "status": "bogus"}).startswith("ERROR");
        assert _update_task_tool({"id": "nope"}).startswith("ERROR");
        assert "write tests" in _list_tasks_tool({});
        assert _delete_task_tool({"id": tid}).startswith("deleted");
        assert _delete_task_tool({"id": tid}).startswith("ERROR");
    } finally {
        plugins.cwd = saved;
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}


test "subagent tool names map legacy aliases and exclude recursion" {
    reg = create_registry();
    for n in ["read_file", "run_command", "grep", "subagent", "compact_context"] {
        register_native(reg, n, "", {}, _noop);
    }
    assert subagent_tool_names(reg, None) == ["grep", "read_file", "run_command"];
    assert subagent_tool_names(reg, ["read", "bash"]) == ["read_file", "run_command"];
    assert subagent_tool_names(reg, ["grep"]) == ["grep"];
    # Nothing matches -> fall back to every usable tool.
    assert subagent_tool_names(reg, ["nonexistent"]) == ["grep", "read_file", "run_command"];
}


test "subagent tool validates its arguments" {
    assert _subagent_tool({"task": ""}).startswith("ERROR");
    assert "unknown subagent" in _subagent_tool({"agent": "no-such-agent-xyz", "task": "x"});
}


test "agent tool specs register on a registry" {
    reg = create_registry();
    register_agent_tools(reg);
    for n in ["list_tasks", "create_task", "update_task", "delete_task", "subagent"] {
        assert n in reg.tools;
    }
}
