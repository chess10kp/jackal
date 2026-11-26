impl _path_abspath(p: str) -> str {
    return str(os.path.abspath(p));
}

impl _path_dirname(p: str) -> str {
    return str(os.path.dirname(p));
}

impl _sessions_dir(cwd: str) -> str {
    return os.path.join(cwd, ".jackal", "sessions");
}

impl _session_path(cwd: str, session_id: str) -> str {
    return os.path.join(_sessions_dir(cwd), session_id + _TRANSCRIPT_SUFFIX);
}

impl _index_path(cwd: str) -> str {
    return os.path.join(_sessions_dir(cwd), _INDEX_NAME);
}

impl is_valid_session_id(session_id: str) -> bool {
    return isinstance(session_id, str) and re.match(_SESSION_ID_PATTERN, session_id) is not None;
}

impl _next_epoch_ms -> int {
    ms = int(time.time() * 1000);
    if ms <= _last_id_ms {
        ms = _last_id_ms + 1;
    }
    _last_id_ms = ms;
    return ms;
}

impl new_session_id -> str {
    return "sess_" + str(_next_epoch_ms());
}

impl _iso_from_ms(ms: int) -> str {
    (secs, msec) = divmod(ms, 1000);
    days: int = secs // 86400;
    rem: int = secs % 86400;
    z: int = days + 719468;
    era: int = z // 146097;
    doe: int = z - era * 146097;
    yoe: int = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365;
    y: int = yoe + era * 400;
    doy: int = doe - (365 * yoe + yoe // 4 - yoe // 100);
    mp: int = (5 * doy + 2) // 153;
    d: int = doy - (153 * mp + 2) // 5 + 1;
    m: int = mp + 3;
    if mp >= 10 {
        m = mp - 9;
    }
    if m <= 2 {
        y += 1;
    }
    hh: int = rem // 3600;
    mi: int = (rem % 3600) // 60;
    ss: int = rem % 60;
    return f"{y:04d}-{m:02d}-{d:02d}T{hh:02d}:{mi:02d}:{ss:02d}.{msec:03d}Z";
}

impl _now_iso -> str {
    return _iso_from_ms(_next_epoch_ms());
}

impl _read_json(path: str) -> any {
    try {
        fh = open(path, "r");
        try {
            return json.loads(fh.read());
        } finally {
            fh.close();
        }
    } except (OSError, ValueError) {
        return None;
    }
}

impl _write_json(path: str, data: any) -> bool {
    try {
        fh = open(path, "w");
        try {
            fh.write(json_pretty(json.dumps(data)));
            fh.write("\n");
            return True;
        } finally {
            fh.close();
        }
    } except OSError {
        return False;
    }
}

impl _is_record(rec: any) -> bool {
    if not isinstance(rec, dict) {
        return False;
    }
    d: dict[str, any] = rec;
    return (
        isinstance(d.get("sessionId"), str)
        and isinstance(d.get("sessionName"), str)
        and isinstance(d.get("cwd"), str)
        and isinstance(d.get("updatedAt"), str)
        and isinstance(d.get("messages"), list)
    );
}

impl _is_index_entry(item: any) -> bool {
    if not isinstance(item, dict) {
        return False;
    }
    d: dict[str, any] = item;
    return (
        isinstance(d.get("id"), str)
        and isinstance(d.get("name"), str)
        and isinstance(d.get("cwd"), str)
        and isinstance(d.get("updatedAt"), str)
        and isinstance(d.get("messageCount"), (int, float))
    );
}

impl _entry_sort_key(rec: dict[str, any]) -> str {
    return str(rec.get("updatedAt", ""));
}

impl _newest_first(entries: list[dict[str, any]]) -> list[dict[str, any]] {
    return sorted(entries, key=_entry_sort_key, reverse=True);
}

impl _read_index(cwd: str) -> tuple[list[dict[str, any]], bool] {
    raw = _read_json(_index_path(cwd));
    valid: list[dict[str, any]] = [];
    if not isinstance(raw, list) {
        return (valid, False);
    }
    for item in raw {
        if not _is_index_entry(item) or not is_valid_session_id(str(item["id"])) {
            continue;
        }
        sid = str(item["id"]);
        if not os.path.exists(_session_path(cwd, sid)) {
            continue;
        }
        valid.append({
            "id": sid,
            "name": str(item["name"]),
            "cwd": str(item["cwd"]),
            "updatedAt": str(item["updatedAt"]),
            "messageCount": int(item["messageCount"]),
        });
    }
    return (valid, True);
}

impl _write_index(cwd: str, entries: list[dict[str, any]]) -> bool {
    sdir = _sessions_dir(cwd);
    try {
        os.makedirs(sdir, exist_ok=True);
    } except OSError {
        return False;
    }
    return _write_json(_index_path(cwd), entries);
}

impl _upsert_index_entry(cwd: str, rec: dict[str, any]) -> bool {
    (entries, _ok) = _read_index(cwd);
    kept: list[dict[str, any]] = [];
    for existing in entries {
        if str(existing["id"]) != str(rec["id"]) {
            kept.append(existing);
        }
    }
    kept.append({
        "id": str(rec["id"]),
        "name": str(rec["name"]),
        "cwd": str(rec["cwd"]),
        "updatedAt": str(rec["updatedAt"]),
        "messageCount": int(rec["messageCount"]),
    });
    return _write_index(cwd, kept);
}

impl _scan_directory(cwd: str) -> list[dict[str, any]] {
    found: list[dict[str, any]] = [];
    sdir = _sessions_dir(cwd);
    if not os.path.isdir(sdir) {
        return found;
    }
    try {
        names = os.listdir(sdir);
    } except OSError {
        return found;
    }
    for name in names {
        if not name.endswith(_TRANSCRIPT_SUFFIX)
            or name == _INDEX_NAME
            or name == _LEGACY_INDEX_NAME
        {
            continue;
        }
        sid = name[:-len(_TRANSCRIPT_SUFFIX)];
        if not is_valid_session_id(sid) {
            continue;
        }
        rec = _read_json(os.path.join(sdir, name));
        if not isinstance(rec, dict) {
            continue;
        }
        rd: dict[str, any] = rec;
        if str(rd.get("sessionId", "")) != sid {
            continue;
        }
        messages = rd.get("messages");
        count = len(messages) if isinstance(messages, list) else 0;
        updated = rd.get("updatedAt");
        found.append({
            "id": sid,
            "name": str(rd.get("sessionName", "")),
            "cwd": str(rd.get("cwd", cwd)),
            "updatedAt": updated if isinstance(updated, str) else "",
            "messageCount": count,
        });
    }
    return found;
}

impl save_session(
    cwd: str, history: list[dict[str, any]], name: str = "", session_id: str = "", model: str = ""
) -> dict[str, any] {
    sid = session_id or new_session_id();
    if not is_valid_session_id(sid) {
        raise ValueError("invalid session id: " + str(sid));
    }
    sdir = _sessions_dir(cwd);
    try {
        os.makedirs(sdir, exist_ok=True);
    } except OSError as exc {
        raise ValueError("cannot create sessions dir: " + str(exc));
    }
    path = _session_path(cwd, sid);

    created = _now_iso();
    prior_name = "";
    prior_model = "";
    existing = _read_json(path);
    if _is_record(existing) {
        ed: dict[str, any] = existing;
        prior_created = ed.get("createdAt");
        if isinstance(prior_created, str) and prior_created {
            created = prior_created;
        }
        recorded = ed.get("sessionName");
        if isinstance(recorded, str) {
            prior_name = recorded;
        }
        prior_rec_model = ed.get("model");
        if isinstance(prior_rec_model, str) {
            prior_model = prior_rec_model;
        }
    }

    trimmed = name.strip();
    if trimmed {
        final_name: str = trimmed;
    } elif prior_name {
        final_name = prior_name;
    } else {
        final_name = _DEFAULT_NAME;
    }

    updated = _now_iso();
    record = {
        "sessionId": sid,
        "sessionName": final_name,
        "cwd": cwd,
        "createdAt": created,
        "updatedAt": updated,
        "messages": history,
    };
    final_model = model.strip() if isinstance(model, str) else "";
    if not final_model {
        final_model = prior_model;
    }
    if final_model {
        record["model"] = final_model;
    }
    if not _write_json(path, record) {
        raise ValueError("cannot write transcript: " + path);
    }
    _upsert_index_entry(
        cwd,
        {
            "id": sid,
            "name": final_name,
            "cwd": cwd,
            "updatedAt": updated,
            "messageCount": len(history),
        },
    );
    return {
        "id": sid,
        "name": final_name,
        "path": path,
        "created": created,
        "updated": updated,
        "messageCount": len(history),
        "model": final_model,
    };
}

impl get_session_record(cwd: str, session_id: str) -> dict[str, any] | None {
    if not is_valid_session_id(session_id) {
        return None;
    }
    rec = _read_json(_session_path(cwd, session_id));
    if not _is_record(rec) {
        return None;
    }
    return rec;
}

impl load_session(cwd: str, session_id: str) -> list[dict[str, any]] {
    if not is_valid_session_id(session_id) {
        return [];
    }
    rec = _read_json(_session_path(cwd, session_id));
    if not _is_record(rec) {
        return [];
    }
    rd: dict[str, any] = rec;
    messages = rd.get("messages");
    if not isinstance(messages, list) {
        return [];
    }
    return messages;
}

impl list_sessions(cwd: str) -> list[dict[str, any]] {
    sdir = _sessions_dir(cwd);
    if not os.path.isdir(sdir) {
        return [];
    }
    (indexed, index_ok) = _read_index(cwd);
    merged: list[dict[str, any]] = [];
    seen: set[str] = set();
    for item in indexed {
        merged.append(item);
        seen.add(str(item["id"]));
    }
    for item in _scan_directory(cwd) {
        if str(item["id"]) not in seen {
            merged.append(item);
        }
    }
    ordered = _newest_first(merged);
    if not index_ok and ordered {
        _write_index(cwd, ordered);
    }
    return ordered;
}

impl rename_session(cwd: str, session_id: str, name: str) -> bool {
    trimmed = name.strip();
    if not trimmed or not is_valid_session_id(session_id) {
        return False;
    }
    rec = _read_json(_session_path(cwd, session_id));
    if not _is_record(rec) {
        return False;
    }
    rd: dict[str, any] = rec;
    if str(rd.get("sessionId", "")) != session_id {
        return False;
    }
    messages = rd.get("messages");
    count = len(messages) if isinstance(messages, list) else 0;
    prior_cwd = rd.get("cwd");
    record_cwd = prior_cwd if isinstance(prior_cwd, str) and prior_cwd else cwd;
    prior_created = rd.get("createdAt");
    created = prior_created if isinstance(prior_created, str) and prior_created else _now_iso();

    updated = _now_iso();
    renamed = {
        "sessionId": session_id,
        "sessionName": trimmed,
        "cwd": record_cwd,
        "createdAt": created,
        "updatedAt": updated,
        "messages": messages if isinstance(messages, list) else [],
    };
    if not _write_json(_session_path(cwd, session_id), renamed) {
        return False;
    }
    _upsert_index_entry(
        cwd,
        {
            "id": session_id,
            "name": trimmed,
            "cwd": record_cwd,
            "updatedAt": updated,
            "messageCount": count,
        },
    );
    return True;
}

impl delete_session(cwd: str, session_id: str) -> bool {
    if not is_valid_session_id(session_id) {
        return False;
    }
    path = _session_path(cwd, session_id);
    existed = os.path.exists(path);
    if existed {
        try {
            os.remove(path);
        } except OSError {
            return False;
        }
    }
    (entries, _ok) = _read_index(cwd);
    remaining: list[dict[str, any]] = [];
    removed_entry = False;
    for item in entries {
        if str(item["id"]) == session_id {
            removed_entry = True;
        } else {
            remaining.append(item);
        }
    }
    if existed or removed_entry {
        _write_index(cwd, remaining);
    }
    return existed or removed_entry;
}
