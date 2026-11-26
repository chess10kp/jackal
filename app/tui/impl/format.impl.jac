impl format_turn(role: str, body: str) -> str {
    text = body.rstrip("\n");
    if not text {
        return "";
    }
    if role == "tool" {
        lines: list[str] = [];
        for line in text.split("\n") {
            lines.append(line or "");
        }
        return "\n".join(lines);
    }
    if role == "user" {
        mark = "◆ You";
    } elif role == "assistant" {
        mark = "◇ Jackal";
    } else {
        mark = "· System";
    }
    lines: list[str] = [mark];
    for line in text.split("\n") {
        if line {
            lines.append("  " + line);
        } else {
            lines.append("");
        }
    }
    return "\n".join(lines);
}

impl format_tool_call(tool: str, args: dict[str, any]) -> str {
    name = str(tool);
    if not isinstance(args, dict) or not args {
        return "call  " + name + "()";
    }
    out: list[str] = ["call  " + name];
    for pair in args.items() {
        key = str(pair[0]);
        val = str(pair[1]);
        if len(val) > 76 {
            val = val[:73] + "…";
        }
        out.append("      " + key + " " + val);
    }
    return "\n".join(out);
}

impl format_tool_result(result_preview: str) -> str {
    if result_preview == "(no output)" {
        return "result  — empty";
    }
    lines: list[str] = ["result"];
    for line in result_preview.split("\n") {
        lines.append("  " + line);
    }
    return "\n".join(lines);
}
