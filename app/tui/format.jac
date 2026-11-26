def format_turn(role: str, body: str) -> str;
def format_tool_call(tool: str, args: dict[str, any]) -> str;
def format_tool_result(result_preview: str) -> str;
