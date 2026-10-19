"""Pure display-preview helpers for TUI transcript entries.

Deliberately import-free (stdlib only implicit): this leaf hosts its own
test annex (tui/preview.test.jac). Annexing tests onto real TUI modules
crashes the compiler (they transitively pull the demoted ui.terminal/
virtual_terminal seams — see tui/popup_pick.jac for the pattern); a pure
leaf avoids both that and the verbatim-replica sync burden.
"""

glob TOOL_RESULT_PREVIEW_LINES: int = 6;
glob TOOL_RESULT_PREVIEW_LINE_CHARS: int = 200;


"""Display-only preview of a tool result for the TUI transcript.

Shows the first TOOL_RESULT_PREVIEW_LINES lines (each capped at
TOOL_RESULT_PREVIEW_LINE_CHARS chars) and, when the result is longer,
a '... (N more lines)' footer. Pure: the full result still reaches the
LLM and the saved transcript — only the on-screen entry shrinks.
"""
def tool_result_preview(result: str, max_lines: int = TOOL_RESULT_PREVIEW_LINES) -> str {
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
        shown.append(f"... ({rest} more lines)");
    }
    return "\n".join(shown);
}
