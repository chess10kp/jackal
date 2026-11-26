test "format_turn omits speaker labels" {
    out = format_turn("user", "hello\nworld");
    assert out == "hello\nworld", str(out);
}

test "format_turn passes tool blocks through without a header" {
    out = format_turn("tool", "call  read\n      path /tmp/a");
    assert out == "call  read\n      path /tmp/a", str(out);
}

test "format_tool_call lists args on separate lines" {
    out = format_tool_call("read", {"path": "/tmp/a.txt"});
    assert out == "call  read\n      path /tmp/a.txt", str(out);
}

test "format_tool_result wraps preview with a result header" {
    out = format_tool_result("line one\nline two");
    assert out == "result\n  line one\n  line two", str(out);
    assert format_tool_result("(no output)") == "result  — empty";
}
