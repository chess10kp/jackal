import os;
import json;

glob TASK_STATUSES: list[str] = ["pending", "in_progress", "completed"],
     SUBAGENT_MAX_ITERS: int = 20,
     SUBAGENT_RESULT_CAP: int = 20_000;

glob NATIVE_TOOL_NAMES: dict[str, str] = {
    "read": "read_file",
    "write": "write_file",
    "edit": "edit_file",
    "bash": "run_command",
    "ls": "list_dir",
};

def _cwd -> str;

def _list_tasks_tool(args: dict[str, any]) -> str;

def _create_task_tool(args: dict[str, any]) -> str;

def _update_task_tool(args: dict[str, any]) -> str;

def _delete_task_tool(args: dict[str, any]) -> str;
def subagent_tool_names(parent: ToolRegistry, allowed: list[str] | None) -> list[str];
def _subagent_approve(name: str, args: dict[str, any]) -> any;

def _subagent_tool(args: dict[str, any]) -> str;

def agent_tool_specs -> list[ToolSpec];

def register_agent_tools(reg: ToolRegistry);
