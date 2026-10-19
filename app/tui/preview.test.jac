"""Unit tests for tui/preview.jac (same-stem annex; imports live in the stem
— the module itself is import-free). Guards the C3 display contract: first
TOOL_RESULT_PREVIEW_LINES lines verbatim, per-line char cap, and the exact
'... (N more lines)' footer when the result is longer. Display-only: nothing
here may assume the full result is unavailable elsewhere."""



test "short result shows verbatim with no footer" {
    out = tool_result_preview("alpha\nbeta\ngamma");
    assert out == "alpha\nbeta\ngamma", out;
    assert "(more lines)" not in out, out;
}


test "long result shows six lines plus an exact-count footer" {
    lines: list[str] = [];
    for i in range(1, 11) {
        lines.append(f"line {i}");
    }
    out = tool_result_preview("\n".join(lines));
    assert out == "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\n... (4 more lines)", out;
}


test "trailing newline does not invent an extra hidden line" {
    out = tool_result_preview("a\nb\nc\nd\ne\nf\ng\n");
    # Seven logical lines: six shown, exactly one more.
    assert out.endswith("\n... (1 more lines)"), out;
}


test "empty and whitespace-only results collapse to a placeholder" {
    assert tool_result_preview("") == "(no output)";
    assert tool_result_preview("\n\n") == "(no output)";
}


test "a single overlong line is char-capped with an ellipsis" {
    long_line = "x" * 500;
    out = tool_result_preview(long_line);
    assert len(out) == TOOL_RESULT_PREVIEW_LINE_CHARS + 3, str(len(out));
    assert out.endswith("x..."), out;
}


test "overlong lines inside a long result are capped, footer still counts lines" {
    a = "y" * 300;
    b = "z" * 250;
    out = tool_result_preview(a + "\n" + b + "\n" + "tail1\ntail2\ntail3\ntail4\ntail5\ntail6\ntail7");
    parts: list[str] = out.split("\n");
    assert len(parts) == 7, out;  # 6 shown + footer
    assert parts[0].endswith("y..."), out;
    assert parts[1].endswith("z..."), out;
    assert parts[5] == "tail4", out;
    assert parts[6] == "... (3 more lines)", out;
}


test "custom max_lines is honored" {
    out = tool_result_preview("one\ntwo\nthree", max_lines=2);
    assert out == "one\ntwo\n... (1 more lines)", out;
}
