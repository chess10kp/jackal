impl json_pretty(raw: str) -> str {
    out: list[str] = [];
    depth: int = 0;
    in_str: bool = False;
    esc: bool = False;
    prev: str = "";
    for ch in raw {
        if in_str {
            out.append(ch);
            if esc {
                esc = False;
            } elif ch == "\\" {
                esc = True;
            } elif ch == "\"" {
                in_str = False;
            }
            prev = ch;
            continue;
        }
        if ch == "\"" {
            in_str = True;
            out.append(ch);
        } elif ch == "{" or ch == "[" {
            depth += 1;
            out.append(ch);
            out.append("\n");
            for i in range(depth) {
                out.append("  ");
            }
        } elif ch == "}" or ch == "]" {
            depth -= 1;
            if prev == "{" or prev == "[" {
                while out and (out[-1] == " " or out[-1] == "\n") {
                    out.pop();
                }
                out.append(ch);
            } else {
                out.append("\n");
                for i in range(depth) {
                    out.append("  ");
                }
                out.append(ch);
            }
        } elif ch == "," {
            out.append(ch);
            out.append("\n");
            for i in range(depth) {
                out.append("  ");
            }
        } else {
            out.append(ch);
        }
        prev = ch;
    }
    return "".join(out);
}
