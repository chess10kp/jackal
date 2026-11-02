"""Pretty-print helper: re-indent compact json.dumps output the way
CPython's `json.dump(data, fh, indent=2)` would have written it. Exists
because the na_stdlib `json.dumps` exposes no `indent` parameter, so
callers that need native lowering re-indent the compact form instead.

Contract (matches CPython indent=2): two spaces per depth level, braces
and brackets break onto their own lines, empty containers stay flat,
string contents pass through untouched (escapes included).
"""


def:pub json_pretty(raw: str) -> str {
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
            for i in range(depth) { out.append("  "); }
        } elif ch == "}" or ch == "]" {
            depth -= 1;
            if prev == "{" or prev == "[" {
                # Empty container: pop the newline+indent just added.
                while out and (out[-1] == " " or out[-1] == "\n") {
                    out.pop();
                }
                out.append(ch);
            } else {
                out.append("\n");
                for i in range(depth) { out.append("  "); }
                out.append(ch);
            }
        } elif ch == "," {
            out.append(ch);
            out.append("\n");
            for i in range(depth) { out.append("  "); }
        } else {
            out.append(ch);
        }
        prev = ch;
    }
    return "".join(out);
}
