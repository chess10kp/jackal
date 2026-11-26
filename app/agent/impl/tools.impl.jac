impl _normalize_abs(path: str) -> str {
    parts: list[str] = [];
    for seg in str(path).replace("\\", "/").split("/") {
        if not seg or seg == "." {
            continue;
        }
        if seg == ".." {
            if parts {
                parts.pop();
            }
            continue;
        }
        parts.append(seg);
    }
    return "/" + "/".join(parts);
}

impl _sandbox_root -> str {
    raw: str = str(os.environ.get(SANDBOX_ROOT_ENV, "")).strip();
    if not raw {
        return "";
    }
    expanded: str = os.path.expanduser(raw);
    if not os.path.isabs(expanded) {
        expanded = os.path.join(os.getcwd(), expanded);
    }
    return _normalize_abs(expanded);
}

impl resolve_path(path: str) -> str {
    if not path {
        raise ValueError("path must not be empty");
    }
    full: str = path if os.path.isabs(path) else os.path.join(os.getcwd(), path);
    sandbox: str = _sandbox_root();
    if not sandbox {
        return full;
    }
    target: str = _normalize_abs(full);
    prefix: str = f"{sandbox.rstrip('/')}/";
    if target != sandbox and not target.startswith(prefix) {
        raise ValueError(f"path escapes {SANDBOX_ROOT_ENV} ({sandbox}): {path}");
    }
    return full;
}

impl read_file(path: str) -> str {
    full = resolve_path(path);
    with open(full, "r", errors="replace") as f {
        text = f.read();
    }
    lines = text.split("\n");
    if len(lines) > READ_LINE_CAP {
        lines = lines[:READ_LINE_CAP];
        lines.append("... [truncated at " + str(READ_LINE_CAP) + " lines]");
    }
    if len(text) > MAX_TOOL_OUTPUT {
        return text[:MAX_TOOL_OUTPUT];
    }
    return "\n".join(lines);
}

impl write_file(path: str, content: str) -> str {
    full: str = resolve_path(path);
    d: str = os.path.dirname(full);
    if d {
        os.makedirs(d, exist_ok=True);
    }
    with open(full, "w") as f {
        f.write(content);
    }
    return f"Wrote {len(content)} bytes to {path}";
}

impl edit_file(path: str, old_text: str, new_text: str) -> str {
    full = resolve_path(path);
    with open(full, "r", errors="replace") as f {
        text = f.read();
    }
    result = apply_edit(text, old_text, new_text);
    if result.startswith("ERROR:") {
        return result;
    }
    with open(full, "w") as f {
        f.write(result);
    }
    return f"Edited {path} ({len(old_text)} -> {len(new_text)} chars)";
}

impl list_dir(path: str) -> str {
    full = resolve_path(path);
    names = sorted(os.listdir(full));
    out: list[str] = [];
    for n in names {
        if n.startswith(".") {
            continue;
        }
        label = n + "/" if os.path.isdir(os.path.join(full, n)) else n;
        out.append(label);
    }
    return "\n".join(out[:500]);
}

impl run_command(cmd: str, timeout_secs: int = 120) -> str {
    try {
        r = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout_secs if timeout_secs > 0 else 120,
            env=_jac_child_env(),
        );
    } except subprocess.TimeoutExpired {
        return f"ERROR: command timed out after {timeout_secs}s";
    }
    out = (r.stdout or "") + (r.stderr or "");
    if len(out) > MAX_TOOL_OUTPUT {
        out = out[:MAX_TOOL_OUTPUT] + "\n... [truncated]";
    }
    return f"exit={r.returncode}\n{out.strip()}";
}

impl _jac_child_env -> dict[str, str] {
    env: dict[str, str] = {};
    for pair in os.environ.items() {
        env[str(pair[0])] = str(pair[1]);
    }
    for key in JAC_CHILD_ENV_DROP {
        env.pop(key, None);
    }
    return env;
}

impl _run_jac_cli(args: list[str], timeout_secs: int = 120) -> str {
    effective = timeout_secs if timeout_secs > 0 else 120;
    argv: list[str] = ["jac"] + args;
    if shutil.which("jac") is None and shutil.which("neojac") is not None {
        argv = ["neojac"] + [("fmt" if a == "format" else a) for a in args];
    }
    try {
        r = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=effective,
            env=_jac_child_env(),
            stdin=subprocess.DEVNULL,
        );
    } except FileNotFoundError {
        return "ERROR: jac CLI not found on PATH";
    } except subprocess.TimeoutExpired {
        return f"ERROR: jac {' '.join(args)} timed out after {effective}s";
    }
    out = (r.stdout or "") + (r.stderr or "");
    if len(out) > MAX_TOOL_OUTPUT {
        out = out[:MAX_TOOL_OUTPUT] + "\n... [truncated]";
    }
    status = "ok" if r.returncode == 0 else f"failed (exit {r.returncode})";
    body = out.strip() if out.strip() else "(no output)";
    return f"jac {' '.join(args)} -> {status}\n{body}";
}

impl jac_check(path: str = ".") -> str {
    full = resolve_path(path);
    if not os.path.exists(full) {
        return f"ERROR: no such file or directory: {path}";
    }
    return _run_jac_cli(["check", full]);
}

impl jac_format(path: str = ".") -> str {
    full = resolve_path(path);
    if not os.path.exists(full) {
        return f"ERROR: no such file or directory: {path}";
    }
    return _run_jac_cli(["format", full]);
}

impl _skip_walk_dir(name: str) -> bool {
    return name.startswith(".") or name in ["node_modules", ".jac", "__pycache__"];
}

impl _search_limit(limit: int) -> int {
    if limit <= 0 {
        return MAX_SEARCH_RESULTS;
    }
    return min(limit, MAX_SEARCH_RESULTS);
}

impl file_glob(pattern: str, base_dir: str = ".", max_results: int = MAX_SEARCH_RESULTS) -> str {
    if not pattern {
        return "ERROR: pattern must not be empty";
    }
    base_path = resolve_path(base_dir);
    if not os.path.isdir(base_path) {
        return f"ERROR: directory not found: {base_dir}";
    }
    cap = _search_limit(max_results);
    matches: list[str] = [];
    for walk_item in os.walk(base_path) {
        current = walk_item[0];
        dirs = walk_item[1];
        files = walk_item[2];
        dirs[:] = [d for d in dirs if not _skip_walk_dir(d)];
        for name in files {
            if name.startswith(".") {
                continue;
            }
            full = os.path.join(current, name);
            rel: str = str(os.path.relpath(str(full), str(base_path))).replace(os.sep, "/");
            if fnmatch.fnmatch(rel, pattern) or fnmatch.fnmatch(name, pattern) {
                matches.append(rel);
            }
        }
    }
    matches.sort();
    truncated = len(matches) > cap;
    visible = matches[:cap];
    out: str = "\n".join(visible);
    if truncated {
        out += ("\n" if out else "") + f"... [truncated at {cap} results]";
    }
    return out;
}

impl content_grep(
    pattern: str, base_dir: str = ".", regex: bool = False, max_results: int = MAX_SEARCH_RESULTS
) -> str {
    if not pattern {
        return "ERROR: pattern must not be empty";
    }
    base_path = resolve_path(base_dir);
    if not os.path.isdir(base_path) {
        return f"ERROR: directory not found: {base_dir}";
    }
    cap = _search_limit(max_results);
    matcher: any = None;
    if regex {
        try {
            matcher = re.compile(pattern);
        } except re.error as e {
            return f"ERROR: invalid regex: {e}";
        }
    }
    matches: list[str] = [];
    for walk_item in os.walk(base_path) {
        current = walk_item[0];
        dirs = walk_item[1];
        files = walk_item[2];
        dirs[:] = [d for d in dirs if not _skip_walk_dir(d)];
        for name in files {
            if name.startswith(".") {
                continue;
            }
            full = os.path.join(current, name);
            rel: str = str(os.path.relpath(str(full), str(base_path))).replace(os.sep, "/");
            try {
                with open(full, "r", errors="replace") as f {
                    lines = f.readlines();
                }
            } except (OSError, UnicodeError) {
                continue;
            }
            for line_item in enumerate(lines, 1) {
                line_no = line_item[0];
                line = line_item[1];
                text = line.rstrip("\n");
                found = matcher.search(text) if regex else pattern in text;
                if found {
                    matches.append(f"{rel}:{line_no}:{text[:500]}");
                }
            }
        }
    }
    matches.sort();
    truncated = len(matches) > cap;
    visible = matches[:cap];
    out: str = "\n".join(visible);
    if truncated {
        out += ("\n" if out else "") + f"... [truncated at {cap} matches]";
    }
    return out;
}

impl _read_file_tool(args: dict[str, any]) -> str {
    return read_file(str(args.get("path", "")));
}

impl _write_file_tool(args: dict[str, any]) -> str {
    return write_file(str(args.get("path", "")), str(args.get("content", "")));
}

impl _edit_file_tool(args: dict[str, any]) -> str {
    return edit_file(
        str(args.get("path", "")), str(args.get("old_text", "")), str(args.get("new_text", ""))
    );
}

impl _list_dir_tool(args: dict[str, any]) -> str {
    return list_dir(str(args.get("path", "")));
}

impl _run_command_tool(args: dict[str, any]) -> str {
    timeout_raw: any = args.get("timeout_secs", 120);
    timeout_secs = int(timeout_raw) if timeout_raw is not None else 120;
    return run_command(str(args.get("cmd", "")), timeout_secs);
}

impl _jac_check_tool(args: dict[str, any]) -> str {
    return jac_check(str(args.get("path", ".")));
}

impl _jac_format_tool(args: dict[str, any]) -> str {
    return jac_format(str(args.get("path", ".")));
}

impl _glob_tool(args: dict[str, any]) -> str {
    max_raw: any = args.get("max_results", MAX_SEARCH_RESULTS);
    max_results = int(max_raw) if max_raw is not None else MAX_SEARCH_RESULTS;
    return file_glob(str(args.get("pattern", "")), str(args.get("base_dir", ".")), max_results);
}

impl _grep_tool(args: dict[str, any]) -> str {
    max_raw: any = args.get("max_results", MAX_SEARCH_RESULTS);
    max_results = int(max_raw) if max_raw is not None else MAX_SEARCH_RESULTS;
    return content_grep(
        str(args.get("pattern", "")),
        str(args.get("base_dir", ".")),
        bool(args.get("regex", False)),
        max_results,
    );
}

impl tool_specs -> list[ToolSpec] {
    return [
        make_tool_spec(
            name="read_file",
            description="Read a text file and return its contents. Use this before editing a file you have not seen this session.",
            parameters={
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Filesystem path to read, relative to the project root.",
                    },
                },
                "required": ["path"],
            },
            handler=_read_file_tool,
        ),
        make_tool_spec(
            name="write_file",
            description="Create or completely overwrite a file with the given content. Prefer edit_file for small changes to existing files.",
            parameters={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Filesystem path to write."},
                    "content": {"type": "string", "description": "Full file content to write."},
                },
                "required": ["path", "content"],
            },
            handler=_write_file_tool,
        ),
        make_tool_spec(
            name="edit_file",
            description="Replace an exact, unique snippet in a file. old_text must match the file byte-for-byte and appear exactly once.",
            parameters={
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Filesystem path of the file to edit.",
                    },
                    "old_text": {
                        "type": "string",
                        "description": "Exact existing text to replace, including indentation.",
                    },
                    "new_text": {"type": "string", "description": "Replacement text."},
                },
                "required": ["path", "old_text", "new_text"],
            },
            handler=_edit_file_tool,
        ),
        make_tool_spec(
            name="list_dir",
            description="List immediate entries of a directory (dotfiles hidden, directories suffixed with /).",
            parameters={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Directory path to list."},
                },
                "required": ["path"],
            },
            handler=_list_dir_tool,
        ),
        make_tool_spec(
            name="run_command",
            description="Run a shell command in the project root and return exit code plus combined stdout/stderr.",
            parameters={
                "type": "object",
                "properties": {
                    "cmd": {"type": "string", "description": "The shell command line to execute."},
                    "timeout_secs": {
                        "type": "integer",
                        "description": "Seconds before the command is killed (default 120).",
                    },
                },
                "required": ["cmd"],
            },
            handler=_run_command_tool,
        ),
        make_tool_spec(
            name="jac_check",
            description="Check Jac files for syntax and type errors using the Jac toolchain (jac check). Prefer this over run_command for validating .jac edits.",
            parameters={
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File or directory to check (default: project root).",
                    },
                },
                "required": [],
            },
            handler=_jac_check_tool,
        ),
        make_tool_spec(
            name="jac_format",
            description="Format Jac files in place with the Jac formatter (jac format). Modifies files; blocked in plan/ask modes.",
            parameters={
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File or directory to format (default: project root).",
                    },
                },
                "required": [],
            },
            handler=_jac_format_tool,
        ),
        make_tool_spec(
            name="glob",
            description="Find files matching a pattern under the project root, skipping hidden and generated directories.",
            parameters={
                "type": "object",
                "properties": {
                    "pattern": {
                        "type": "string",
                        "description": "Shell-style file pattern such as **/*.jac.",
                    },
                    "base_dir": {
                        "type": "string",
                        "description": "Directory to search (default .).",
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Maximum results, capped at 100.",
                    },
                },
                "required": ["pattern"],
            },
            handler=_glob_tool,
        ),
        make_tool_spec(
            name="grep",
            description="Search file contents for a literal or regular-expression pattern under the project root.",
            parameters={
                "type": "object",
                "properties": {
                    "pattern": {
                        "type": "string",
                        "description": "Text or regular expression to search for.",
                    },
                    "base_dir": {
                        "type": "string",
                        "description": "Directory to search (default .).",
                    },
                    "regex": {
                        "type": "boolean",
                        "description": "Use regex matching instead of literal matching.",
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Maximum matches, capped at 100.",
                    },
                },
                "required": ["pattern"],
            },
            handler=_grep_tool,
        ),
    ] + [
        make_tool_spec(
            name="web_search",
            description="Search the web and return result titles, URLs, and snippets.",
            parameters={
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query."},
                    "num_results": {"type": "integer", "description": "Maximum results."},
                },
                "required": ["query"],
            },
            handler=_web_search_tool,
        ),
        make_tool_spec(
            name="web_fetch",
            description="Fetch an http(s) URL and return readable text.",
            parameters={
                "type": "object",
                "properties": {"url": {"type": "string", "description": "http(s) URL to fetch."}},
                "required": ["url"],
            },
            handler=_web_fetch_tool,
        ),
    ];
}

impl default_registry -> ToolRegistry {
    reg = create_registry();
    for spec in tool_specs() {
        register_native_spec(reg, spec);
    }
    return reg;
}
