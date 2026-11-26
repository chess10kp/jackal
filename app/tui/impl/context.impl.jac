impl _explorer_walk(dir_path: str, base_root: str, depth: int, out: list[str]) {
    if depth > _EXPLORER_MAX_DEPTH or len(out) >= _EXPLORER_MAX_FILES {
        return;
    }
    rules: list[str] = [];
    try {
        rules = _load_ignore_rules(base_root, dir_path);
    } except Exception {
        rules = [];
    }
    try {
        entries = sorted(os.listdir(dir_path));
    } except OSError {
        return;
    }
    subdirs: list[str] = [];
    for name in entries {
        full = os.path.join(dir_path, name);
        is_dir = os.path.isdir(full);
        rel = str(os.path.relpath(full, base_root)).replace(os.sep, "/");
        rel_cmp = rel + "/" if is_dir else rel;
        try {
            if _match_ignore_pattern(rel_cmp, rules) {
                continue;
            }
        } except Exception {}
        if is_dir {
            if name.startswith(".") or name in _EXPLORER_SKIP_DIRS {
                continue;
            }
            subdirs.append(name);
        } elif len(out) < _EXPLORER_MAX_FILES {
            out.append(rel);
        }
    }
    for name in subdirs {
        _explorer_walk(os.path.join(dir_path, name), base_root, depth + 1, out);
        if len(out) >= _EXPLORER_MAX_FILES {
            return;
        }
    }
}

impl _explorer_file_entries(cwd: str) -> dict[str, list[str]] {
    out: list[str] = [];
    _explorer_walk(cwd, cwd, 1, out);
    return {"rows": list(out), "ids": list(out)};
}

impl _skills_picker_entries(skills: list[dict[str, any]]) -> dict[str, list[str]] {
    if not skills {
        return {"rows": ["no skills found"], "ids": ["__header__"]};
    }
    rows: list[str] = [];
    ids: list[str] = [];
    for s in skills {
        name = str(s.get("name", ""));
        desc = str(s.get("description", ""));
        label = name + (" — " + desc if desc else "");
        if s.get("disableModelInvocation", False) is True {
            label += "  · hidden";
        }
        rows.append(label);
        ids.append(name);
    }
    return {"rows": rows, "ids": ids};
}

impl _format_mentions(paths: list[str]) -> str {
    parts: list[str] = [];
    seen: set[str] = set();
    for p in paths {
        rel = str(p);
        if not rel or rel in seen {
            continue;
        }
        seen.add(rel);
        if re.search(r"\s", rel) is not None {
            parts.append("@\"" + rel + "\"");
        } else {
            parts.append("@" + rel);
        }
    }
    if not parts {
        return "";
    }
    return " ".join(parts) + " ";
}

impl _take_quoted_mentions(text: str) -> tuple[str, list[dict[str, any]]] {
    mentions: list[dict[str, any]] = [];
    spans: list[tuple[int, int]] = [];
    for m in re.finditer(_QUOTED_MENTION_PATTERN, text) {
        inner: str = str(m.group(1));
        path_part: str = inner;
        rng: dict[str, any] | None = None;
        outer_start: any = m.group(2);
        outer_end: any = m.group(3);
        if outer_start {
            outer_range: str = str(outer_start) + ("-" + str(outer_end) if outer_end else "");
            parsed_outer: dict[str, any] | None = parse_line_range(outer_range);
            if parsed_outer is not None {
                rng = parsed_outer;
            }
        } else {
            cm = re.search(r":(\d+)(?:-(\d+))?$", inner);
            if cm is not None {
                inner_range: str = inner[cm.start() + 1:];
                parsed_inner: dict[str, any] | None = parse_line_range(inner_range);
                if parsed_inner is not None {
                    path_part = inner[:cm.start()];
                    rng = parsed_inner;
                }
            }
        }
        if not is_valid_file_path(path_part) {
            continue;
        }
        spans.append((m.start(), m.end()));
        mentions.append({
            "raw": str(m.group(0)),
            "path": path_part,
            "start": m.start(),
            "end": m.end(),
            "line_range": rng,
        });
    }
    if not mentions {
        return (text, []);
    }
    parts: list[str] = [];
    last: int = 0;
    for sp in spans {
        parts.append(text[last:sp[0]]);
        last = sp[1];
    }
    parts.append(text[last:]);
    return ("".join(parts), mentions);
}

impl _expand_quoted_context(cwd: str, text: str) -> str {
    lifted: tuple[str, list[dict[str, any]]] = _take_quoted_mentions(text);
    cleaned: str = lifted[0];
    quotes: list[dict[str, any]] = lifted[1];
    if not quotes {
        return expand_context_input(cwd, text);
    }
    base: str = "";
    body: str = cleaned.strip();
    if body {
        try {
            base = expand_context_input(cwd, body);
        } except Exception {
            base = body;
        }
    }
    blocks: list[str] = [];
    for q in quotes {
        qpath: str = str(q.get("path", ""));
        qrng: any = q.get("line_range");
        try {
            got: tuple[str, int] = _load_file_slice(cwd, qpath, qrng);
            blocks.append(got[0]);
        } except (OSError, ValueError) as exc {
            blocks.append('<file path="' + qpath + '" error="' + str(exc) + '" />');
        }
    }
    if "Attached context:" in base {
        return base + "\n" + "\n".join(blocks);
    }
    head: str = base + "\n\n" if base else "";
    return head + "Attached context:\n" + "\n".join(blocks);
}

impl _insert_into_draft(app: LiveShell, addition: str) {
    if not addition {
        return;
    }
    draft = app.shell.prompt.draft + addition;
    app.shell.prompt.draft = draft;
    app.shell.prompt.caret = len(draft);
    app.shell.prompt.history_index = -1;
    app.dirty = True;
}

impl _open_explorer_picker(app: LiveShell) -> str {
    entries = _explorer_file_entries(os.getcwd());
    if not entries["rows"] {
        return "no readable project files";
    }
    opened = _open_picker(app, "EXPLORER", entries["rows"], entries["ids"], multi=True);
    if not opened {
        return "picker unavailable (overlay busy)";
    }
    return "";
}
