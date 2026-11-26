impl _path_dirname(p: str) -> str {
    return str(os.path.dirname(p));
}

impl _path_abspath(p: str) -> str {
    return str(os.path.abspath(p));
}

impl _path_relpath(p: str, start: str) -> str {
    return str(os.path.relpath(p, start));
}

impl checkpoints_dir(cwd: str) -> str {
    return os.path.join(cwd, ".jackal", "checkpoints");
}

impl _checkpoint_path(cwd: str, name: str) -> str {
    return os.path.join(checkpoints_dir(cwd), name);
}

impl validate_checkpoint_name(name: str) -> dict[str, any] {
    if not name or not name.strip() {
        return {"valid": False, "error": "Checkpoint name cannot be empty"};
    }
    if len(name) > 100 {
        return {"valid": False, "error": "Checkpoint name must be 100 characters or less"};
    }
    for ch in _INVALID_NAME_CHARS {
        if ch in name {
            return {"valid": False, "error": "Checkpoint name contains invalid characters"};
        }
    }
    if name.startswith(".") or name.endswith(".") or name.startswith(" ") or name.endswith(" ") {
        return {"valid": False, "error": "Checkpoint name cannot start or end with a dot or space"};
    }
    return {"valid": True};
}

impl _generate_checkpoint_name -> str {
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat();
    ts = ts.replace(":", "-").replace(".", "-").replace("T", "-");
    return "checkpoint-" + ts;
}

impl _generate_description(messages: list[dict[str, any]]) -> str {
    for msg in messages {
        if not isinstance(msg, dict) {
            continue;
        }
        role = msg.get("role");
        content = msg.get("content");
        if role == "user" and isinstance(content, str) and content.strip() {
            text = content.strip();
            if len(text) > _DESCRIPTION_LENGTH {
                return text[:_DESCRIPTION_LENGTH] + "...";
            }
            return text;
        }
    }
    return "Empty conversation";
}

impl _git_commit_hash(cwd: str) -> str | None {
    try {
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=cwd, capture_output=True, text=True, timeout=5
        );
    } except Exception as exc {
        log_debug("checkpoints.git_head", "git rev-parse failed", {"cwd": cwd, "error": str(exc)});
        return None;
    }
    if result.returncode != 0 {
        return None;
    }
    return result.stdout.strip();
}

impl get_modified_files(cwd: str) -> list[str] {
    all_files: list[str] = [];
    try {
        modified = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=10,
        );
        untracked = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=10,
        );
        mod_files: list[str] = [];
        if modified.returncode == 0 {
            mod_files = [f for f in modified.stdout.strip().split("\n") if f];
        }
        untracked_files: list[str] = [];
        if untracked.returncode == 0 {
            untracked_files = [f for f in untracked.stdout.strip().split("\n") if f];
        }
        seen: set[str] = set();
        for fp in mod_files + untracked_files {
            if fp not in seen {
                seen.add(fp);
                all_files.append(fp);
            }
        }
    } except Exception as exc {
        log_exception("checkpoints.modified_files", exc, {"cwd": cwd});
    }
    return all_files[:_MAX_CHECKPOINT_FILES];
}

impl _resolve_rel(cwd: str, rel: str) -> str {
    return _path_abspath(os.path.join(cwd, rel));
}

impl _capture_files(cwd: str, file_paths: list[str]) -> dict[str, str] {
    snapshots: dict[str, str] = {};
    for fp in file_paths {
        try {
            abs_path: str = _resolve_rel(cwd, fp);
            fh: any = open(abs_path, "r");
            try {
                content = fh.read();
            } finally {
                fh.close();
            }
            rel: str = _path_relpath(abs_path, cwd).replace("\\\\", "/");
            snapshots[rel] = content;
        } except Exception as exc {
            log_warn(
                "checkpoints.capture",
                "skipping unreadable file",
                {"path": fp, "cwd": cwd, "error": str(exc)},
            );
        }
    }
    return snapshots;
}

impl _dir_size(dir_path: str) -> int {
    total = 0;
    try {
        for dir_entry in os.scandir(dir_path) {
            if dir_entry.is_dir() {
                total += _dir_size(dir_entry.path);
            } elif dir_entry.is_file() {
                total += dir_entry.stat().st_size;
            }
        }
    } except OSError {}
    return total;
}

impl _write_json(path: str, data: any) -> bool {
    fh: any = None;
    try {
        fh = open(path, "w");
        fh.write(json_pretty(json.dumps(data)));
        fh.write("\n");
    } except OSError {
        return False;
    } finally {
        if fh is not None {
            fh.close();
        }
    }
    return True;
}

impl _load_json_file(path: str) -> any {
    fh = open(path, "r");
    try {
        return json.loads(fh.read());
    } finally {
        fh.close();
    }
}

impl create_checkpoint(
    cwd: str,
    messages: list[dict[str, any]],
    provider: str,
    model: str,
    name: str = "",
    modified_files: list[str] | None = None,
) -> dict[str, any] {
    os.makedirs(checkpoints_dir(cwd), exist_ok=True);

    trimmed = name.strip() if isinstance(name, str) else "";
    checkpoint_name = trimmed or _generate_checkpoint_name();
    validation = validate_checkpoint_name(checkpoint_name);
    if not validation["valid"] {
        err = validation.get("error");
        raise ValueError(str(err) if err else "Invalid checkpoint name");
    }

    dir_path = _checkpoint_path(cwd, checkpoint_name);
    if os.path.exists(dir_path) {
        raise ValueError("Checkpoint '" + checkpoint_name + "' already exists");
    }

    files_to_snapshot: list[str] = modified_files
        if modified_files is not None
        else get_modified_files(cwd);
    file_snapshots = _capture_files(cwd, files_to_snapshot);

    now = datetime.datetime.now(datetime.timezone.utc).isoformat();
    metadata = {
        "name": checkpoint_name,
        "timestamp": now,
        "messageCount": len(messages),
        "filesChanged": list(file_snapshots.keys()),
        "provider": {"name": provider, "model": model},
        "description": _generate_description(messages),
        "gitCommitHash": _git_commit_hash(cwd),
    };

    conversation = {"messages": messages};

    os.makedirs(dir_path, exist_ok=True);
    if not _write_json(os.path.join(dir_path, _METADATA_NAME), metadata) {
        raise ValueError("cannot write checkpoint metadata: " + dir_path);
    }
    if not _write_json(os.path.join(dir_path, _CONVERSATION_NAME), conversation) {
        raise ValueError("cannot write checkpoint conversation: " + dir_path);
    }

    if file_snapshots {
        files_dir = os.path.join(dir_path, "files");
        os.makedirs(files_dir, exist_ok=True);
        for rel_path in file_snapshots {
            fp: str = os.path.join(files_dir, rel_path);
            os.makedirs(_path_dirname(fp), exist_ok=True);
            fh: any = open(fp, "w");
            try {
                fh.write(file_snapshots[rel_path]);
            } finally {
                fh.close();
            }
        }
    }
    return metadata;
}

impl load_checkpoint(cwd: str, name: str) -> dict[str, any] {
    dir_path = _checkpoint_path(cwd, name);
    if not os.path.exists(dir_path) {
        raise ValueError("Checkpoint '" + name + "' does not exist");
    }

    metadata = _load_json_file(os.path.join(dir_path, _METADATA_NAME));
    conversation = _load_json_file(os.path.join(dir_path, _CONVERSATION_NAME));

    file_snapshots: dict[str, str] = {};
    files_dir = os.path.join(dir_path, "files");
    if os.path.exists(files_dir) {
        changed = metadata.get("filesChanged") if isinstance(metadata, dict) else None;
        if isinstance(changed, list) {
            for rel_path in changed {
                try {
                    fh = open(os.path.join(files_dir, str(rel_path)), "r");
                    try {
                        file_snapshots[str(rel_path)] = fh.read();
                    } finally {
                        fh.close();
                    }
                } except Exception as exc {
                    log_warn(
                        "checkpoints.load",
                        "missing snapshot file",
                        {"rel": str(rel_path), "error": str(exc)},
                    );
                }
            }
        }
    }
    return {"metadata": metadata, "conversation": conversation, "fileSnapshots": file_snapshots};
}

impl _timestamp_key(item: dict[str, any]) -> str {
    return str(item["metadata"].get("timestamp", ""));
}

impl list_checkpoints(cwd: str) -> list[dict[str, any]] {
    cp_dir = checkpoints_dir(cwd);
    try {
        os.makedirs(cp_dir, exist_ok=True);
    } except OSError as exc {
        log_warn("checkpoints.list", "cannot create store dir", {"dir": cp_dir, "error": str(exc)});
    }

    items: list[dict[str, any]] = [];
    try {
        entries = os.listdir(cp_dir);
    } except OSError as exc {
        log_warn("checkpoints.list", "cannot read store dir", {"dir": cp_dir, "error": str(exc)});
        return [];
    }

    for name_entry in entries {
        dir_path = os.path.join(cp_dir, name_entry);
        if not os.path.isdir(dir_path) {
            continue;
        }
        meta_path = os.path.join(dir_path, _METADATA_NAME);
        if not os.path.exists(meta_path) {
            continue;
        }
        try {
            metadata = _load_json_file(meta_path);
            items.append({
                "name": name_entry,
                "metadata": metadata,
                "sizeBytes": _dir_size(dir_path),
            });
        } except Exception as exc {
            log_warn(
                "checkpoints.list",
                "skipping unreadable checkpoint",
                {"name": str(name_entry), "error": str(exc)},
            );
        }
    }
    return sorted(items, key=_timestamp_key, reverse=True);
}

impl delete_checkpoint(cwd: str, name: str) {
    dir_path = _checkpoint_path(cwd, name);
    if not os.path.exists(dir_path) {
        raise ValueError("Checkpoint '" + name + "' does not exist");
    }
    shutil.rmtree(dir_path);
}

impl restore_checkpoint_files(cwd: str, snapshots: dict[str, str]) {
    errors: list[str] = [];
    for rel_path in snapshots {
        try {
            abs_path: str = _resolve_rel(cwd, str(rel_path));
            os.makedirs(_path_dirname(abs_path), exist_ok=True);
            fh: any = open(abs_path, "w");
            try {
                fh.write(snapshots[rel_path]);
            } finally {
                fh.close();
            }
        } except Exception as exc {
            errors.append("Failed to restore " + str(rel_path) + ": " + str(exc));
        }
    }
    if errors {
        raise RuntimeError("Failed to restore some files:\n" + "\n".join(errors));
    }
}

impl _plural(n: int, unit: str) -> str {
    return str(n) + " " + unit + ("s" if n != 1 else "");
}

impl _changed_count(m: dict[str, any]) -> int {
    changed = m.get("filesChanged");
    if isinstance(changed, list) {
        return len(changed);
    }
    return 0;
}

impl format_relative_time(timestamp: str) -> str {
    now = datetime.datetime.now(datetime.timezone.utc).timestamp();
    t = datetime.datetime.fromisoformat(timestamp).timestamp();
    diff_minutes = int((now - t) / 60);
    diff_hours = diff_minutes // 60;
    diff_days = diff_hours // 24;

    if diff_minutes < 1 {
        return "just now";
    }
    if diff_minutes < 60 {
        return _plural(diff_minutes, "min") + " ago";
    }
    if diff_hours < 24 {
        return _plural(diff_hours, "hr") + " ago";
    }
    if diff_days < 7 {
        return _plural(diff_days, "day") + " ago";
    }
    return datetime.datetime.fromisoformat(timestamp).strftime("%Y-%m-%d");
}

impl _size_label(size_bytes: any) -> str {
    if size_bytes {
        return str(round(int(size_bytes) / 1024)) + "KB";
    }
    return "?";
}

impl format_checkpoint_overlay_row(item: dict[str, any]) -> str {
    m = item["metadata"];
    when = format_relative_time(str(m["timestamp"]));
    size_kb = _size_label(item.get("sizeBytes"));
    return (
        str(m["name"])
        + " \u2014 "
        + str(m["messageCount"])
        + " msgs, "
        + str(_changed_count(m))
        + " files \u2014 "
        + when
        + " ("
        + size_kb
        + ")"
    );
}

impl format_checkpoint_list(items: list[dict[str, any]]) -> str {
    if not items {
        return "No checkpoints. Use /checkpoint create [name].";
    }
    lines: list[str] = [];
    for item in items {
        m: dict[str, any] = item["metadata"];
        when = datetime.datetime.fromisoformat(str(m["timestamp"])).strftime("%Y-%m-%d %H:%M");
        size_kb = _size_label(item.get("sizeBytes"));
        lines.append(
            "- "
                + str(m["name"])
                + " ("
                + when
                + ", "
                + str(m["messageCount"])
                + " msgs, "
                + str(_changed_count(m))
                + " files, "
                + size_kb
                + ")",
        );
    }
    return "Checkpoints:\n" + "\n".join(lines);
}
