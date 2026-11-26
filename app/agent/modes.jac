import re;

glob DEV_MODES: list[str] = ["normal", "auto-accept", "yolo", "plan", "ask"];

glob READ_ONLY_MODES: list[str] = ["plan", "ask"];

glob READ_ONLY_MODE_BLOCKED_TOOLS: set[str] = {
    "write",
    "edit",
    "jac_format",
    "jac_fix",
    "jac_create",
    "create_task",
    "update_task",
    "delete_task",
    "format_jac",
    "execute_command",
    "write_file",
    "edit_file",
};

glob READ_ONLY_TOOLS: set[str] = {
    "read_file",
    "list_dir",
    "glob",
    "grep",
    "web_search",
    "web_fetch",
    "list_tasks",
    "jac_check",
};

glob MCP_READ_ONLY_TOOLS: set[str] = set();

glob PLAN_MODE_SYSTEM_APPENDIX: str = """

## Plan mode (active)

You are in **plan mode**: explore, analyze, and produce a clear implementation plan. You must **not** modify project source files.
""";

glob ASK_MODE_SYSTEM_APPENDIX: str = """

## Ask mode (active)

You are in **ask mode**: answer questions, explain code, and explore the codebase. You must **not** modify project source files.
""";

glob DESTRUCTIVE_BASH_PATTERNS: list[str] = [
    r"rm\s+-rf\s+\/(?!\w)",
    r"\brm\s+-rf\s+~",
    r"\brm\s+-rf\s+\$\{?HOME\}?",
    r"\bmkfs\b",
    r"\bdd\s+if=",
    r":\(\)\{:\|:&\};:",
    r">\s*\/dev\/sd[a-z]",
    r"\bchmod\s+-R\s+000\b",
    r"\bgit\s+reset\s+--hard\b",
    r"\bgit\s+push\s+(--force|-f)\b",
    r"\bgit\s+clean\s+-[a-z]*f",
    r"\bgit\s+branch\s+-[dD]\s+",
    r"\bgit\s+stash\s+(drop|clear)\b",
    r"\bgit\s+reflog\s+expire\b",
    r"\bgit\s+filter-branch\b",
    r"\bdrop\s+database\b",
    r"\btruncate\s+table\b",
];
def is_read_only_mode(mode: str) -> bool;
def is_tool_blocked_in_read_only_mode(tool_name: str) -> bool;
def is_tool_blocked(mode: str, tool_name: str) -> bool;
def is_mcp_tool(tool_name: str) -> bool;
def register_mcp_read_only_tools(names: list[str]);
def unregister_mcp_read_only_tools(names: list[str]);
def read_only_mode_block_reason(tool_name: str, mode: str) -> str;
def cycle_mode(current: str) -> str;
def parse_mode_flag(args: list[str]) -> str | dict[str, str] | None;
def is_destructive_bash(cmd: str) -> bool;
def system_prompt_for_mode(base_prompt: str, mode: str) -> str;
def requires_approval(mode: str, tool_name: str, cmd: str) -> str;
