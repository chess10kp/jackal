impl is_read_only_mode(mode: str) -> bool {
    return mode in READ_ONLY_MODES;
}

impl is_tool_blocked_in_read_only_mode(tool_name: str) -> bool {
    return tool_name in READ_ONLY_MODE_BLOCKED_TOOLS;
}

impl is_tool_blocked(mode: str, tool_name: str) -> bool {
    return is_read_only_mode(mode) and is_tool_blocked_in_read_only_mode(tool_name);
}

impl is_mcp_tool(tool_name: str) -> bool {
    return tool_name.startswith("mcp_");
}

impl register_mcp_read_only_tools(names: list[str]) {
    for n in names {
        MCP_READ_ONLY_TOOLS.add(str(n));
    }
}

impl unregister_mcp_read_only_tools(names: list[str]) {
    for n in names {
        MCP_READ_ONLY_TOOLS.discard(str(n));
    }
}

impl read_only_mode_block_reason(tool_name: str, mode: str) -> str {
    if is_mcp_tool(tool_name) {
        return (
            'MCP tool "'
            + tool_name
            + '" is not marked read-only, so it is blocked in '
            + mode
            + ' mode. Mark the server "read_only": true (or list "read_only_tools") in the mcp config to allow it.'
        );
    }
    if mode == "ask" {
        return 'Tool "'
            + tool_name
            + '" cannot modify files in ask mode. Switch to normal mode (Shift+Tab) to make changes.';
    }
    return 'Tool "'
        + tool_name
        + '" cannot modify files in plan mode. Switch to normal mode (Shift+Tab) to implement changes.';
}

impl cycle_mode(current: str) -> str {
    idx = -1;
    for i in range(len(DEV_MODES)) {
        if DEV_MODES[i] == current {
            idx = i;
            break;
        }
    }
    if idx < 0 {
        return DEV_MODES[0];
    }
    return DEV_MODES[(idx + 1) % len(DEV_MODES)];
}

impl parse_mode_flag(args: list[str]) -> str | dict[str, str] | None {
    for i in range(len(args)) {
        raw: str | None = None;
        arg = args[i];
        if arg == "--mode" and i + 1 < len(args) {
            raw = args[i + 1];
        } elif arg.startswith("--mode=") {
            raw = arg[len("--mode="):];
        }
        if raw is None {
            continue;
        }
        if raw in DEV_MODES {
            return raw;
        }
        return {"error": raw};
    }
    return None;
}

impl is_destructive_bash(cmd: str) -> bool {
    command = cmd.strip();
    if not command {
        return False;
    }
    for pattern in DESTRUCTIVE_BASH_PATTERNS {
        if re.search("(?i)" + pattern, command) is not None {
            return True;
        }
    }
    return False;
}

impl system_prompt_for_mode(base_prompt: str, mode: str) -> str {
    if mode == "plan" {
        if "## Plan mode (active)" in base_prompt {
            return base_prompt;
        }
        return base_prompt + PLAN_MODE_SYSTEM_APPENDIX;
    }
    if mode == "ask" {
        if "## Ask mode (active)" in base_prompt {
            return base_prompt;
        }
        return base_prompt + ASK_MODE_SYSTEM_APPENDIX;
    }
    return base_prompt;
}

impl requires_approval(mode: str, tool_name: str, cmd: str) -> str {
    if is_tool_blocked(mode, tool_name) {
        return "blocked";
    }
    if mode == "yolo" {
        return "auto";
    }
    if mode == "auto-accept" {
        if tool_name == "run_command" or tool_name == "bash" {
            if is_destructive_bash(cmd) {
                return "confirm";
            }
        }
        return "auto";
    }
    if mode == "plan" or mode == "ask" {
        if (tool_name == "run_command" or tool_name == "bash") and is_destructive_bash(cmd) {
            return "blocked";
        }
        if is_mcp_tool(tool_name) and tool_name not in MCP_READ_ONLY_TOOLS {
            return "blocked";
        }
        return "auto";
    }
    if tool_name in READ_ONLY_TOOLS {
        return "auto";
    }
    return "confirm";
}
