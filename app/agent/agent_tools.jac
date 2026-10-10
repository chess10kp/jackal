"""Session-aware tools for the model: the task board and subagent delegation.

These need live session state (cwd, mode, model, cancel handle, registry), so
they live outside tools.jac and are registered by session_boot via
register_agent_tools.
"""

import os;
import json;

import from .session_state { plugins, get_model_state, get_thinking_level_state, get_mode_state }
import from .registry { ToolRegistry, register_native_spec, create_registry, get_tool }
import from .tool_spec { make_tool_spec, ToolSpec }
import from .tasks { load_tasks, add_task, update_tasks, remove_task_by_id, format_tasks_list }
import from .subagents {
    list_subagents,
    get_subagent,
    EXCLUDED_SUBAGENT_TOOLS,
    load_project_model_overrides,
}
import from .modes { requires_approval, is_read_only_mode, read_only_mode_block_reason }
import from .llm { react_loop, make_transport, credential_error }
import from .system { SYSTEM_PROMPT }

glob TASK_STATUSES: list[str] = ["pending", "in_progress", "completed"],
     SUBAGENT_MAX_ITERS: int = 20,
     SUBAGENT_RESULT_CAP: int = 20_000;

"""Legacy subagent tool names (agent markdown frontmatter) -> native names."""
glob NATIVE_TOOL_NAMES: dict[str, str] = {
    "read": "read_file",
    "write": "write_file",
    "edit": "edit_file",
    "bash": "run_command",
    "ls": "list_dir",
};


def _cwd() -> str {
    return plugins.cwd if plugins.cwd else os.getcwd();
}


def _list_tasks_tool(args: dict[str, any]) -> str {
    return format_tasks_list(load_tasks(_cwd()));
}


def _create_task_tool(args: dict[str, any]) -> str {
    title: str = str(args.get("title", "")).strip();
    if not title {
        return "ERROR: title is required";
    }
    task = add_task(_cwd(), title, str(args.get("description", "") or ""));
    return "created [" + str(task["id"]) + "] " + title;
}


def _update_task_tool(args: dict[str, any]) -> str {
    task_id: str = str(args.get("id", "")).strip();
    if not task_id {
        return "ERROR: id is required";
    }
    upd: dict[str, any] = {"id": task_id};
    if args.get("status") is not None {
        status: str = str(args["status"]);
        if status not in TASK_STATUSES {
            return "ERROR: status must be one of " + ", ".join(TASK_STATUSES);
        }
        upd["status"] = status;
    }
    if args.get("title") is not None { upd["title"] = str(args["title"]); }
    if args.get("description") is not None { upd["description"] = str(args["description"]); }
    known: bool = False;
    for t in load_tasks(_cwd()) {
        if str(t["id"]) == task_id { known = True; break; }
    }
    if not known {
        return "ERROR: unknown task id " + task_id;
    }
    return format_tasks_list(update_tasks(_cwd(), [upd]));
}


def _delete_task_tool(args: dict[str, any]) -> str {
    task_id: str = str(args.get("id", "")).strip();
    got = remove_task_by_id(_cwd(), task_id);
    if got is None {
        return "ERROR: unknown task id " + task_id;
    }
    return "deleted [" + task_id + "] " + str(got["title"]);
}


"""Native tool names a subagent may use: the agent's frontmatter allow-list
(legacy names mapped, `mcp:` prefix stripped) intersected with the parent
registry. Excluded tools (including this one) never pass; an allow-list that
matches nothing falls back to every non-excluded tool."""
def subagent_tool_names(parent: ToolRegistry, allowed: list[str] | None) -> list[str] {
    wanted: set[str] = set();
    if allowed {
        for raw in allowed {
            name: str = str(raw).strip();
            if name.startswith("mcp:") { name = name[4:]; }
            if name { wanted.add(NATIVE_TOOL_NAMES.get(name, name)); }
        }
    }
    excluded: set[str] = set(EXCLUDED_SUBAGENT_TOOLS);
    excluded.add("subagent");
    usable: list[str] = [];
    for n in sorted(parent.tools.keys()) {
        if n not in excluded { usable.append(n); }
    }
    if not wanted { return usable; }
    picked: list[str] = [];
    for n in usable {
        if n in wanted { picked.append(n); }
    }
    return picked if picked else usable;
}


"""Approver for nested loops: subagents cannot prompt the user, so
confirm-gated calls are refused unless the session mode auto-approves them."""
def _subagent_approve(name: str, args: dict[str, any]) -> any {
    cmd: str = str(args.get("cmd", "")) if isinstance(args, dict) else "";
    mode: str = get_mode_state();
    policy: str = requires_approval(mode, name, cmd);
    if policy == "auto" { return True; }
    if policy == "blocked" and is_read_only_mode(mode) {
        return read_only_mode_block_reason(name, mode);
    }
    return (
        "subagents cannot ask for approval; \"" + name + "\" needs approval in "
        + mode + " mode (switch to auto-accept or yolo, or do it in the main agent)"
    );
}


def _subagent_tool(args: dict[str, any]) -> str {
    agent_name: str = str(args.get("agent", "")).strip();
    task: str = str(args.get("task", "")).strip();
    if not task {
        return "ERROR: task is required";
    }
    system: str = SYSTEM_PROMPT;
    allowed: list[str] | None = None;
    model: str = get_model_state();
    if agent_name and agent_name != "general" {
        agent = get_subagent(_cwd(), agent_name);
        if agent is None {
            names: list[str] = [];
            for a in list_subagents(_cwd()) { names.append(str(a["name"])); }
            return "ERROR: unknown subagent " + agent_name + " (available: general"
                + ("" if not names else ", " + ", ".join(names)) + ")";
        }
        body: str = str(agent.get("systemPrompt", "") or "");
        if body { system = SYSTEM_PROMPT + "\n\n" + body; }
        raw_tools: any = agent.get("tools");
        if isinstance(raw_tools, list) { allowed = raw_tools; }
        overrides = load_project_model_overrides(_cwd());
        want: str = str(overrides.get(agent_name, "") or agent.get("model", "") or overrides.get("__default__", "") or "");
        if want and want != "inherit" and not credential_error(want) { model = want; }
    }
    parent: ToolRegistry = plugins.reg if plugins.reg is not None else create_registry();
    child: ToolRegistry = create_registry();
    for n in subagent_tool_names(parent, allowed) {
        ent = get_tool(parent, n);
        if ent is not None { child.tools[n] = ent; }
    }
    messages: list[dict[str, any]] = [
        {"role": "system", "content": system + "\n\nYou are a subagent. Complete the task, then reply with a concise final report; the caller sees only that report."},
        {"role": "user", "content": task},
    ];
    tools_used: list[int] = [0];

    def on_event(kind: str, data: dict[str, any]) {
        if kind == "tool_call" { tools_used[0] = tools_used[0] + 1; }
    }
    try {
        transport = make_transport(model, get_thinking_level_state());
        answer: str = react_loop(
            messages, [], transport, on_event,
            max_iters=SUBAGENT_MAX_ITERS, reg=child, bridge=None,
            cancel=plugins.active_cancel, approve=_subagent_approve,
        );
    } except Exception as e {
        return "ERROR: subagent failed: " + str(e);
    }
    if not answer {
        return "ERROR: subagent returned no answer (" + str(tools_used[0]) + " tool calls)";
    }
    return answer[:SUBAGENT_RESULT_CAP];
}


def agent_tool_specs() -> list[ToolSpec] {
    return [
        make_tool_spec(
            name="list_tasks",
            description="Show the project task board (.jackal/tasks.json) with ids and statuses.",
            parameters={"type": "object", "properties": {}, "required": []},
            handler=_list_tasks_tool,
        ),
        make_tool_spec(
            name="create_task",
            description="Add a pending task to the task board. Use this to plan multi-step work and track progress; keep titles short and actionable.",
            parameters={
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "Short task title."},
                    "description": {"type": "string", "description": "Optional detail."},
                },
                "required": ["title"],
            },
            handler=_create_task_tool,
        ),
        make_tool_spec(
            name="update_task",
            description="Update a task's status (pending, in_progress, completed), title, or description. Mark one task in_progress while working on it and completed as soon as it is done.",
            parameters={
                "type": "object",
                "properties": {
                    "id": {"type": "string", "description": "Task id from list_tasks/create_task."},
                    "status": {"type": "string", "enum": TASK_STATUSES},
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                },
                "required": ["id"],
            },
            handler=_update_task_tool,
        ),
        make_tool_spec(
            name="delete_task",
            description="Remove a task from the board by id.",
            parameters={
                "type": "object",
                "properties": {"id": {"type": "string", "description": "Task id."}},
                "required": ["id"],
            },
            handler=_delete_task_tool,
        ),
        make_tool_spec(
            name="subagent",
            description=(
                "Delegate a self-contained task (research, codebase search, focused edits) to a subagent "
                "with a fresh context. It runs its own tool loop and returns only a final report, keeping "
                "your context small. agent=\"general\" (default) or a named subagent from the project catalog. "
                "Subagents cannot ask the user for approval."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "agent": {"type": "string", "description": "Subagent name (default \"general\")."},
                    "task": {"type": "string", "description": "Complete, self-contained instructions including all context the subagent needs."},
                },
                "required": ["task"],
            },
            handler=_subagent_tool,
        ),
    ];
}


def register_agent_tools(reg: ToolRegistry) {
    for spec in agent_tool_specs() {
        register_native_spec(reg, spec);
    }
}
