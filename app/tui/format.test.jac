"""Unit tests for tui/format.jac (display-only transcript blocks)."""


test "format_turn adds header, indent, and trailing spacer" {
    out = format_turn("user", "hello\nworld");
    assert out == "◆ You\n\n    hello\n    world\n\n", out;
}


test "format_tool_call lists args on separate lines" {
    out = format_tool_call("read", {"path": "/tmp/a.txt"});
    assert out == "call  read\n        path  /tmp/a.txt", out;
}


test "format_tool_result wraps preview with a result header" {
    out = format_tool_result("line one\nline two");
    assert out == "result\n    line one\n    line two", out;
    assert format_tool_result("(no output)") == "result  — empty";
}
