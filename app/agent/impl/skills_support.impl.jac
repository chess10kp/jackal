impl _base_name(p: str) -> str {
    return p.replace(os.sep, "/").rsplit("/", 1)[-1];
}

impl _dir_name(p: str) -> str {
    s = p.replace(os.sep, "/");
    idx = s.rfind("/");
    if idx == -1 {
        return s;
    }
    if idx == 0 {
        return "/";
    }
    return s[:idx];
}

impl _rel_path(target: str, start: str) -> str {
    return str(os.path.relpath(target, start));
}

impl _abs_path(p: str) -> str {
    return str(os.path.abspath(p));
}

impl _canonical(p: str) -> str {
    try {
        return str(os.path.realpath(p));
    } except OSError {
        return _abs_path(p);
    }
}

impl _is_abs(p: str) -> bool {
    return bool(os.path.isabs(p));
}

impl _user_home -> str {
    tilde: any = "~";
    return str(os.path.expanduser(tilde));
}

impl _parse_scalar(value: str) -> any {
    trimmed = value.strip();
    if not trimmed {
        return "";
    }
    if (trimmed.startswith('"') and trimmed.endswith('"'))
        or (trimmed.startswith("'") and trimmed.endswith("'"))
    {
        return trimmed[1:-1];
    }
    if trimmed.startswith("[") and trimmed.endswith("]") {
        inner = trimmed[1:-1].strip();
        if not inner {
            return [];
        }
        parts: list[str] = [];
        for part in inner.split(",") {
            piece = part.strip().strip("\"'");
            if piece {
                parts.append(piece);
            }
        }
        return parts;
    }
    return trimmed;
}

impl parse_frontmatter(content: str) -> tuple[dict[str, any], str] {
    fm: dict[str, any] = {};
    normalized = content.replace("\r\n", "\n");
    if not normalized.startswith("---") {
        return (fm, normalized);
    }
    end_index = normalized.find("\n---", 3);
    if end_index == -1 {
        return (fm, normalized);
    }
    block = normalized[4:end_index];
    body = normalized[end_index + 4:].strip();

    current_key = "";
    list_items: list[str] = [];
    for raw_line in block.split("\n") {
        line = raw_line.rstrip();
        list_match = re.match(r"^\s*-\s+(.*)$", line);
        if list_match and current_key {
            list_items.append(str(list_match.group(1)).strip().strip("\"'").strip("'\""));
            continue;
        }
        if current_key and list_items {
            fm[current_key] = list_items[:];
        }
        list_items = [];
        current_key = "";
        key_match = re.match(r"^([\w-]+):\s*(.*)$", line);
        if not key_match {
            continue;
        }
        key = str(key_match.group(1));
        value = str(key_match.group(2) or "");
        if not value.strip() {
            current_key = key;
            continue;
        }
        fm[key] = _parse_scalar(value);
    }
    if current_key and list_items {
        fm[current_key] = list_items[:];
    }
    return (fm, body);
}

impl frontmatter_string(value: any) -> str | None {
    if value is None {
        return None;
    }
    if isinstance(value, list) {
        parts: list[str] = [];
        for item in value {
            parts.append(str(item));
        }
        return ", ".join(parts);
    }
    return str(value);
}

impl _gitignore_parse_rules(content: str, prefix: str) -> list[str] {
    rules: list[str] = [];
    for line in content.splitlines() {
        trimmed = line.strip();
        if not trimmed or (trimmed.startswith("#") and not trimmed.startswith("\\#")) {
            continue;
        }
        pattern = line;
        negated = False;
        if pattern.startswith("!") {
            negated = True;
            pattern = pattern[1:];
        } elif pattern.startswith("\\!") {
            pattern = pattern[1:];
        }
        if pattern.startswith("/") {
            pattern = pattern[1:];
        }
        prefixed = prefix + pattern if prefix else pattern;
        if negated {
            rules.append("!" + prefixed);
        } else {
            rules.append(prefixed);
        }
    }
    return rules;
}

impl _load_ignore_rules(root_dir: str, subdir: str) -> list[str] {
    rel = _rel_path(subdir, root_dir).replace(os.sep, "/");
    prefix = rel + "/" if rel != "." else "";
    rules: list[str] = [];
    for fname in IGNORE_FILE_NAMES {
        fpath = os.path.join(subdir, fname);
        if not os.path.isfile(fpath) {
            continue;
        }
        try {
            fh = open(fpath);
            try {
                rules.extend(_gitignore_parse_rules(fh.read(), prefix));
            } finally {
                fh.close();
            }
        } except (OSError, UnicodeDecodeError) {}
    }
    return rules;
}

impl _match_ignore_pattern(path: str, rules: list[str]) -> bool {
    result = False;
    for rule in rules {
        rule_str = str(rule);
        negated = rule_str.startswith("!");
        pattern = rule_str[1:] if negated else rule_str;
        dir_only = pattern.endswith("/");
        if dir_only {
            pattern = pattern.rstrip("/");
        }
        if pattern.startswith("**/") {
            sub = pattern[3:];
            if fnmatch.fnmatch(_base_name(path), sub) {
                result = not negated;
            }
        } elif "/" in pattern {
            if fnmatch.fnmatch(path, pattern) {
                result = not negated;
            }
        } elif fnmatch.fnmatch(_base_name(path), pattern) {
            result = not negated;
        }
    }
    return result;
}

impl _validate_name(name: str) -> list[str] {
    errors: list[str] = [];
    if len(name) > MAX_NAME_LENGTH {
        errors.append(f"name exceeds {MAX_NAME_LENGTH} characters ({len(name)})");
    }
    if re.fullmatch(r"[a-z0-9-]+", name) is None {
        errors.append(
            "name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)"
        );
    }
    if name.startswith("-") or name.endswith("-") {
        errors.append("name must not start or end with a hyphen");
    }
    if "--" in name {
        errors.append("name must not contain consecutive hyphens");
    }
    return errors;
}

impl _validate_description(description: str | None) -> list[str] {
    errors: list[str] = [];
    if not description or description.strip() == "" {
        errors.append("description is required");
    } elif len(description) > MAX_DESCRIPTION_LENGTH {
        errors.append(
            f"description exceeds {MAX_DESCRIPTION_LENGTH} characters ({len(description)})"
        );
    }
    return errors;
}

impl _warning(message: str, path: str) -> dict[str, any] {
    return {"type": "warning", "message": message, "path": path, "collision": None};
}

impl _load_skill_from_file(file_path: str, source: str) -> tuple[dict[str, any]
    | None, list[dict[str, any]]] {
    diagnostics: list[dict[str, any]] = [];
    result: dict[str, any] | None = None;
    try {
        fh = open(file_path, encoding="utf-8");
        try {
            raw = fh.read();
        } finally {
            fh.close();
        }
        (fm, _body) = parse_frontmatter(raw);
        skill_dir = _dir_name(file_path);
        parent_name = _base_name(skill_dir);
        desc = frontmatter_string(fm.get("description"));
        disable_raw = frontmatter_string(fm.get("disable-model-invocation"));
        disable_invocation = str(disable_raw or "").lower() == "true";

        for err in _validate_description(desc) {
            diagnostics.append(_warning(err, file_path));
        }

        raw_name = frontmatter_string(fm.get("name"));
        name: str = (raw_name or "").strip();
        if not name {
            name = parent_name;
        }
        for err in _validate_name(name) {
            diagnostics.append(_warning(err, file_path));
        }

        if not desc or not str(desc).strip() {
            return (None, diagnostics);
        }
        result = {
            "name": name,
            "description": str(desc).strip(),
            "filePath": file_path,
            "baseDir": skill_dir,
            "source": source,
            "disableModelInvocation": disable_invocation,
        };
    } except Exception as exc {
        diagnostics.append(_warning(str(exc), file_path));
        return (None, diagnostics);
    }
    return (result, diagnostics);
}
