"""Structured JSONL debug logging for the agent harness (observability floor).

The harness has ~120 `except Exception {}` sites that keep the no-raise seam
contract by swallowing the failure entirely. That is the right *control flow*
and the wrong *observability*: a checkpoint that silently captures zero files
or a plugin bridge that never connects leaves no trace anywhere. This module
is the sink those sites can call without giving up the contract.

Enablement (opt-in; nothing is written unless asked for):

    JACKAL_LOG=1          -> <cwd>/.jackal/logs/<date>-<pid>.jsonl
    JACKAL_LOG=/tmp/x.log -> that path (parent directories created)
    JACKAL_LOG=0|off      -> disabled (the default when unset)
    JACKAL_LOG_LEVEL      -> debug|info|warn|error (default: info)

Contract: every public function here is *total*. A bad path, a full disk, an
unserializable field, or a raised exception inside the logger itself must
never propagate into the caller — `log_*` is safe to call from inside an
`except` block that is deliberately not re-raising.

One JSON object per line, keys: ts, level, source, msg, pid, and optional
`fields` with the caller's structured payload.
"""

import os;
import json;
import datetime;
import traceback;

glob LOG_LEVELS: dict[str, int] = {
        "debug": 10,
        "info": 20,
        "warn": 30,
        "warning": 30,
        "error": 40,
        "off": 100,
    },
    LOG_ENV: str = "JACKAL_LOG",
    LEVEL_ENV: str = "JACKAL_LOG_LEVEL",
    DEFAULT_LOG_DIR: str = ".jackal/logs",
    DEFAULT_LEVEL: str = "info",
    MAX_FIELD_DEPTH: int = 3,
    MAX_FIELD_ITEMS: int = 20,
    MAX_STRING_LEN: int = 400,
    MAX_TRACEBACK_LEN: int = 4000;

glob _FALSEY: list[str] = ["0", "off", "false", "no", "none", ""],
     _TRUTHY: list[str] = ["1", "on", "true", "yes"];


"""The configured sink path, or "" when logging is disabled.
`JACKAL_LOG=1` (or on/true/yes) means the default per-process file under
<cwd>/.jackal/logs; any other non-falsey value is used as a literal path."""
def log_sink() -> str {
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
sem log_sink = "Resolve the JSONL sink path from JACKAL_LOG; empty means disabled.";


"""Numeric threshold from JACKAL_LOG_LEVEL (default `info`). Unknown values
fall back to `info` rather than disabling logging silently."""
def log_threshold() -> int {
    raw: str = str(os.environ.get(LEVEL_ENV, DEFAULT_LEVEL)).strip().lower();
    if raw in LOG_LEVELS {
        return LOG_LEVELS[raw];
    }
    return LOG_LEVELS[DEFAULT_LEVEL];
}
sem log_threshold = "Numeric severity threshold for the env-configured log level.";


"""True when at least one record at `level` would be written."""
def log_enabled(level: str = "info") -> bool {
    sink: str = log_sink();
    if not sink {
        return False;
    }
    want: str = str(level).strip().lower();
    sev: int = LOG_LEVELS[want] if want in LOG_LEVELS else LOG_LEVELS["info"];
    return sev >= log_threshold();
}
sem log_enabled = "Cheap pre-check for callers that would build an expensive payload.";


"""Coerce a caller payload into JSON-safe primitives (bounded depth/size).
Never raises: unknown objects become their repr, truncated."""
def safe_fields(value: any, depth: int = 0) -> any {
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
sem safe_fields = "Best-effort JSON-safe projection of arbitrary logging payloads.";


"""Short, safe repr for leaf values the logger does not understand."""
def _short_repr(value: any) -> str {
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


"""Append one JSONL record. Total function: returns False when the record was
not written (disabled, below threshold, or any I/O error)."""
def log_event(
    level: str,
    source: str,
    message: str,
    fields: dict[str, any] | None = None,
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
sem log_event = "Write one structured JSONL log record; never raises into the caller.";


"""Record a caught exception without changing control flow. Safe outside an
`except` block (traceback is then empty). `fields` is merged into the record."""
def log_exception(
    source: str,
    exc: any,
    fields: dict[str, any] | None = None,
) -> bool {
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
            tb = traceback.format_exc();
        } except Exception {
            tb = "";
        }
        if tb and tb.strip() != "NoneType: None" {
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
sem log_exception = "Log a swallowed exception (type, message, traceback) at error level.";


def:pub log_debug(source: str, message: str, fields: dict[str, any] | None = None) -> bool {
    return log_event("debug", source, message, fields);
}

def log_info(source: str, message: str, fields: dict[str, any] | None = None) -> bool {
    return log_event("info", source, message, fields);
}

def:pub log_warn(source: str, message: str, fields: dict[str, any] | None = None) -> bool {
    return log_event("warn", source, message, fields);
}

"""Read back a JSONL sink as records (tests + `/debug` style inspection).
Unreadable or malformed lines are skipped, never raised."""
def read_log(path: str) -> list[dict[str, any]] {
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
sem read_log = "Parse a JSONL log file into records, skipping malformed lines.";
