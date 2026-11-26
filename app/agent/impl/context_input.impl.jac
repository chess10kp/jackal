impl _path_abspath(p: str) -> str {
    return str(os.path.abspath(p));
}

impl _path_normpath(p: str) -> str {
    return str(os.path.normpath(p));
}

impl is_valid_file_path(file_path: str) -> bool {
    if not isinstance(file_path, str) or not file_path.strip() {
        return False;
    }
    segments = file_path.replace("\\", "/").split("/");
    if ".." in segments {
        return False;
    }
    if file_path.startswith("/") or file_path.startswith("\\") {
        return False;
    }
    if re.match(_WINDOWS_DRIVE_PATTERN, file_path) is not None {
        return False;
    }
    if "\0" in file_path {
        return False;
    }
    return True;
}

impl parse_line_range(range_str: str) -> dict[str, any] | None {
    if not range_str {
        return None;
    }
    parts = range_str.split("-");
    if len(parts) == 1 {
        if not parts[0].isdigit() {
            return None;
        }
        line = int(parts[0]);
        if line <= 0 {
            return None;
        }
        return {"start": line};
    }
    if len(parts) == 2 {
        if not parts[0].isdigit() or not parts[1].isdigit() {
            return None;
        }
        start = int(parts[0]);
        end = int(parts[1]);
        if start <= 0 or end < start {
            return None;
        }
        return {"start": start, "end": end};
    }
    return None;
}

impl parse_file_mentions(input_text: str) -> list[dict[str, any]] {
    mentions: list[dict[str, any]] = [];
    for m in re.finditer(_FILE_MENTION_PATTERN, input_text) {
        file_path = str(m.group(1));
        if not is_valid_file_path(file_path) {
            continue;
        }
        line_start = m.group(2);
        line_end = m.group(3);
        mention: dict[str, any] = {
            "raw_text": m.group(0),
            "file_path": file_path,
            "start_index": m.start(),
            "end_index": m.end(),
            "line_range": None,
        };
        if line_start {
            start = int(line_start);
            end = int(line_end) if line_end else None;
            if start > 0 and (end is None or end >= start) {
                mention["line_range"] = {"start": start, "end": end};
            }
        }
        mentions.append(mention);
    }
    return mentions;
}

impl parse_mention_token(raw: str) -> dict[str, any] {
    colon = raw.rfind(":");
    if colon <= 0 {
        return {"path": raw};
    }
    path_part = raw[:colon];
    range_part = raw[colon + 1:];
    if re.match(_MENTION_RANGE_PATTERN, range_part) is None {
        return {"path": raw};
    }
    rng = parse_line_range(range_part);
    if rng is None {
        return {"path": raw};
    }
    return {"path": path_part, "startLine": rng["start"], "endLine": rng.get("end", rng["start"])};
}

impl get_current_file_mention(input_text: str, cursor_position: int = -1) -> dict[str, any] | None {
    pos = cursor_position if cursor_position >= 0 else len(input_text);

    start = -1;
    idx = pos - 1;
    while idx >= 0 {
        ch = input_text[idx];
        if ch == "@" {
            start = idx;
            break;
        }
        if ch == " " or ch == "\t" or ch == "\n" {
            break;
        }
        idx -= 1;
    }
    if start < 0 {
        return None;
    }

    end = pos;
    idx = pos;
    while idx < len(input_text) {
        ch = input_text[idx];
        if ch == " " or ch == "\t" or ch == "\n" or ch == "@" {
            break;
        }
        end = idx + 1;
        idx += 1;
    }

    full = input_text[start + 1:end];
    range_match = re.match(_CURSOR_RANGE_FULL, full);
    if range_match is not None {
        mention = str(range_match.group(1));
        range_suffix = str(range_match.group(2));
    } else {
        mention = full;
        range_suffix = "";
    }
    return {"mention": mention, "start": start, "end": end, "rangeSuffix": range_suffix};
}

impl _safe_resolve(cwd: str, input_path: str) -> str {
    abs_path = _path_normpath(_path_abspath(os.path.join(cwd, input_path)));
    root_dir = _path_normpath(_path_abspath(cwd) + "/");
    if not (abs_path + "/").startswith(root_dir) and abs_path != root_dir {
        raise ValueError("Path escapes cwd: " + input_path);
    }
    return abs_path;
}

impl _load_file_slice(cwd: str, mention: str, line_range: any = None) -> tuple[str, int] {
    token_start: any = None;
    token_end: any = None;
    if line_range is not None {
        token_start = line_range.get("start");
        token_end = line_range.get("end");
        if token_end is None {
            token_end = token_start;
        }
        file_path = mention;
    } else {
        parsed = parse_mention_token(mention);
        file_path = str(parsed.get("path", mention));
        token_start = parsed.get("startLine");
        token_end = parsed.get("endLine");
    }

    abs_path = _safe_resolve(cwd, file_path);
    fh = open(abs_path, "r");
    try {
        content = fh.read();
    } finally {
        fh.close();
    }

    text = content;
    label = file_path;
    if isinstance(token_start, int) {
        lines = content.split("\n");
        lo = max(1, token_start) - 1;
        hi = min(len(lines), token_end if isinstance(token_end, int) else token_start);
        text = "\n".join(lines[lo:hi]);
        suffix = "";
        if isinstance(token_end, int) and token_end != token_start {
            suffix = "-" + str(token_end);
        }
        label = file_path + ":" + str(token_start) + suffix;
    }

    if len(text) > _MAX_FILE_CHARS {
        text = text[:_MAX_FILE_CHARS] + "\n...[truncated at " + str(_MAX_FILE_CHARS) + " chars]";
    }

    block = '<file path="' + label + '">\n```\n' + text + "\n```\n</file>";
    return (block, len(text));
}

impl _run_inline_command(cwd: str, command: str) -> str {
    try {
        proc = subprocess.run(
            ["bash", "-lc", command],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=_COMMAND_TIMEOUT_SECS,
        );
    } except subprocess.TimeoutExpired {
        return "Command timed out after 60 seconds";
    } except OSError as exc {
        return "Command failed: " + str(exc);
    }
    parts: list[str] = [];
    if proc.stdout {
        parts.append("stdout:\n" + proc.stdout);
    }
    if proc.stderr {
        parts.append("stderr:\n" + proc.stderr);
    }
    parts.append("exit=" + str(proc.returncode));
    return "\n".join(parts)[:_MAX_FILE_CHARS];
}

impl expand_context_input(cwd: str, text: str) -> str {
    trimmed = text.strip();
    if not trimmed {
        return text;
    }

    if trimmed.startswith("!") {
        command = trimmed[1:].strip();
        if not command {
            return text;
        }
        output = _run_inline_command(cwd, command);
        return "\n".join([
            "User ran inline command: `" + command + "`",
            "<command_output>",
            output,
            "</command_output>",
            "Continue based on the command output above.",
        ]);
    }

    mentions = parse_file_mentions(trimmed);
    if not mentions {
        return text;
    }

    blocks: list[str] = [];
    seen: set[str] = set();
    total_chars = 0;
    for mention in mentions {
        raw = str(mention["raw_text"]);
        if raw in seen {
            continue;
        }
        seen.add(raw);
        file_path = str(mention["file_path"]);
        try {
            (block, chars) = _load_file_slice(cwd, file_path, mention["line_range"]);
            blocks.append(block);
            total_chars += chars;
        } except (OSError, ValueError) as exc {
            blocks.append('<file path="' + file_path + '" error="' + str(exc) + '" />');
        }
    }

    header = trimmed;
    if total_chars >= _TOKEN_WARN_CHARS {
        header = ("[Warning: attached files ~" + str(total_chars // 4) + " tokens]\n" + trimmed);
    }
    return header + "\n\nAttached context:\n" + "\n".join(blocks);
}
