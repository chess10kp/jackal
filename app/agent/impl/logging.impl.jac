impl log_sink -> str {
    raw: str = str(os.environ.get(LOG_ENV, "")).strip();
    low: str = raw.lower();
    if low in _FALSEY {
        return "";
    }
    if low in _TRUTHY {
        stamp: str = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d");
        name: str = stamp + "-" + str(os.getpid()) + ".jsonl";
        return os.path.join(os.getcwd(), DEFAULT_LOG_DIR, name);
    }
    expanded: str = os.path.expanduser(raw);
    if not os.path.isabs(expanded) {
        expanded = os.path.join(os.getcwd(), expanded);
    }
    return expanded;
}

impl log_threshold -> int {
    raw: str = str(os.environ.get(LEVEL_ENV, DEFAULT_LEVEL)).strip().lower();
    if raw in LOG_LEVELS {
        return LOG_LEVELS[raw];
    }
    return LOG_LEVELS[DEFAULT_LEVEL];
}

impl log_enabled(level: str = "info") -> bool {
    sink: str = log_sink();
    if not sink {
        return False;
    }
    want: str = str(level).strip().lower();
    sev: int = LOG_LEVELS[want] if want in LOG_LEVELS else LOG_LEVELS["info"];
    return sev >= log_threshold();
}

impl safe_fields(value: any, depth: int = 0) -> any {
    try {
        if value is None or isinstance(value, bool) or isinstance(value, int) {
            return value;
        }
        if isinstance(value, float) {
            return value;
        }
        if isinstance(value, str) {
            text: str = value;
            if len(text) > MAX_STRING_LEN {
                return text[:MAX_STRING_LEN] + "...";
            }
            return text;
        }
        if depth >= MAX_FIELD_DEPTH {
            return _short_repr(value);
        }
        if isinstance(value, dict) {
            out: dict[str, any] = {};
            count: int = 0;
            for pair in value.items() {
                if count >= MAX_FIELD_ITEMS {
                    out["..."] = "truncated";
                    break;
                }
                out[str(pair[0])] = safe_fields(pair[1], depth + 1);
                count += 1;
            }
            return out;
        }
        if isinstance(value, (list, tuple, set)) {
            items: list[any] = [];
            count2: int = 0;
            for item in value {
                if count2 >= MAX_FIELD_ITEMS {
                    items.append("...");
                    break;
                }
                items.append(safe_fields(item, depth + 1));
                count2 += 1;
            }
            return items;
        }
        return _short_repr(value);
    } except Exception {
        return "<unloggable>";
    }
}

impl _short_repr(value: any) -> str {
    try {
        text: str = repr(value);
        if len(text) > MAX_STRING_LEN {
            return text[:MAX_STRING_LEN] + "...";
        }
        return text;
    } except Exception {
        return "<unrepr-able>";
    }
}

impl log_event(
    level: str, source: str, message: str, fields: dict[str, any] | None = None
) -> bool {
    try {
        sink: str = log_sink();
        if not sink {
            return False;
        }
        want: str = str(level).strip().lower();
        sev: int = LOG_LEVELS[want] if want in LOG_LEVELS else LOG_LEVELS["info"];
        if sev < log_threshold() {
            return False;
        }
        record: dict[str, any] = {
            "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "level": want if want in LOG_LEVELS else "info",
            "source": str(source),
            "msg": str(message),
            "pid": os.getpid(),
        };
        if fields is not None {
            record["fields"] = safe_fields(fields);
        }
        line: str = json.dumps(record, ensure_ascii=False);
        parent: str = os.path.dirname(sink);
        if parent and not os.path.isdir(parent) {
            os.makedirs(parent, exist_ok=True);
        }
        fh: any = open(sink, "a", encoding="utf-8");
        try {
            fh.write(line + "\n");
        } finally {
            fh.close();
        }
        return True;
    } except Exception {
        return False;
    }
}

impl _format_tb(exc: any) -> str {
    if exc is None or not isinstance(exc, BaseException) {
        return "";
    }
    e: BaseException = exc;
    frame: any = e.__traceback__;
    if frame is None {
        return "";
    }
    lines: list[str] = ["Traceback (most recent call last):"];
    while frame is not None {
        code: any = frame.tb_frame.f_code;
        lines.append(f'  File "{code.co_filename}", line {frame.tb_lineno}, in {code.co_name}');
        frame = frame.tb_next;
    }
    lines.append(type(e).__name__ + ": " + str(e));
    return "\n".join(lines) + "\n";
}

impl log_exception(source: str, exc: any, fields: dict[str, any] | None = None) -> bool {
    try {
        payload: dict[str, any] = {};
        if fields is not None {
            converted: any = safe_fields(fields);
            if isinstance(converted, dict) {
                payload = converted;
            }
        }
        kind: str = "Exception";
        detail: str = "";
        if exc is not None {
            try {
                kind = type(exc).__name__;
            } except Exception {
                kind = "Exception";
            }
            try {
                detail = str(exc);
            } except Exception {
                detail = "<no message>";
            }
        }
        payload["exception"] = kind;
        payload["detail"] = safe_fields(detail);
        tb: str = "";
        try {
            tb = _format_tb(exc);
        } except Exception {
            tb = "";
        }
        if tb {
            if len(tb) > MAX_TRACEBACK_LEN {
                tb = tb[-MAX_TRACEBACK_LEN:];
            }
            payload["traceback"] = tb;
        }
        return log_event("error", source, kind + ": " + detail, payload);
    } except Exception {
        return False;
    }
}

impl log_debug(source: str, message: str, fields: dict[str, any] | None = None) -> bool {
    return log_event("debug", source, message, fields);
}

impl log_info(source: str, message: str, fields: dict[str, any] | None = None) -> bool {
    return log_event("info", source, message, fields);
}

impl log_warn(source: str, message: str, fields: dict[str, any] | None = None) -> bool {
    return log_event("warn", source, message, fields);
}

impl read_log(path: str) -> list[dict[str, any]] {
    records: list[dict[str, any]] = [];
    try {
        fh: any = open(path, "r", encoding="utf-8");
        try {
            for line in fh.read().splitlines() {
                text: str = line.strip();
                if not text {
                    continue;
                }
                try {
                    parsed: any = json.loads(text);
                    if isinstance(parsed, dict) {
                        records.append(parsed);
                    }
                } except Exception {
                    continue;
                }
            }
        } finally {
            fh.close();
        }
    } except Exception {
        return [];
    }
    return records;
}
