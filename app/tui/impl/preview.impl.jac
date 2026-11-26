impl tool_result_preview(result: str, max_lines: int = TOOL_RESULT_PREVIEW_LINES) -> str {
    text = result.rstrip("\n");
    if not text {
        return "(no output)";
    }
    lines: list[str] = text.split("\n");
    shown: list[str] = [];
    for line in lines[:max_lines] {
        if len(line) > TOOL_RESULT_PREVIEW_LINE_CHARS {
            shown.append(line[:TOOL_RESULT_PREVIEW_LINE_CHARS] + "...");
        } else {
            shown.append(line);
        }
    }
    if len(lines) > max_lines {
        rest: int = len(lines) - max_lines;
        shown.append(f"…  +{rest} lines");
    }
    return "\n".join(shown);
}
