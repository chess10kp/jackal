glob TOOL_RESULT_PREVIEW_LINES: int = 6,
     TOOL_RESULT_PREVIEW_LINE_CHARS: int = 200;
def tool_result_preview(result: str, max_lines: int = TOOL_RESULT_PREVIEW_LINES) -> str;
