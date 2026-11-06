"""Tests for agent/logging.jac — same-stem annex (merged with the base
module at test time).

The contract under test is total-ness: logging must never raise, never write
when disabled, and never let a bad payload or a bad sink escape into the
caller of a swallowed `except` block.
"""

import os;
import json;
import tempfile;
import shutil;
import io;


obj _Weird {
    has label: str = "weird";

    def __repr__() -> str {
        return "<weird object>";
    }
}


obj _EnvSnapshot {
    has values: dict[str, str | None] = {};
}


def _set_env(env: dict[str, str]) -> _EnvSnapshot {
    old: dict[str, str | None] = {};
    for (key, value) in env.items() {
        old[key] = os.environ.get(key);
        os.environ[key] = value;
    }
    return _EnvSnapshot(values=old);
}


def _restore_env(snapshot: _EnvSnapshot) {
    for (key, value) in snapshot.values.items() {
        if value is None {
            os.environ.pop(key, None);
        } else {
            os.environ[key] = value;
        }
    }
}


test "logging is off by default and writes nothing" {
    wrote: bool = False;
    env_snapshot = _set_env({"JACKAL_LOG": "", "JACKAL_LOG_LEVEL": "debug"});
    try {
        wrote = log_event("error", "test", "should not appear");
    } finally {
        _restore_env(env_snapshot);
    }
    assert wrote is False, wrote;
    assert log_sink() == "";
    assert not log_enabled("error");
}


test "explicit sink path writes one JSON object per event" {
    tmp = tempfile.mkdtemp(prefix="jackal-log-test-");
    try {
        sink = os.path.join(tmp, "nested", "debug.jsonl");
        env_snapshot = _set_env({"JACKAL_LOG": sink, "JACKAL_LOG_LEVEL": "debug"});
        wrote: bool = False;
        try {
            log_info("agent.tools", "read_file ok", {"path": "a.txt", "bytes": 3});
            wrote = log_info("agent.tools", "second", None);
        } finally {
            _restore_env(env_snapshot);
        }
        assert wrote is True, wrote;
        assert os.path.exists(sink);
        records = read_log(sink);
        assert len(records) == 2, records;
        first = records[0];
        assert first["level"] == "info", first;
        assert first["source"] == "agent.tools", first;
        assert first["msg"] == "read_file ok", first;
        assert first["fields"]["path"] == "a.txt", first;
        assert first["fields"]["bytes"] == 3, first;
        assert isinstance(first["ts"], str) and len(first["ts"]) > 10, first;
        assert first["pid"] == os.getpid(), first;
        assert not ("fields" in records[1]), records[1];
    } finally {
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "JACKAL_LOG=1 uses the per-process .jackal/logs file" {
    tmp = tempfile.mkdtemp(prefix="jackal-log-default-");
    cwd = os.getcwd();
    try {
        os.chdir(tmp);
        env_snapshot = _set_env({"JACKAL_LOG": "1", "JACKAL_LOG_LEVEL": "info"});
        sink: str = "";
        try {
            log_warn("bridge", "extension timed out");
            sink = log_sink();
        } finally {
            _restore_env(env_snapshot);
        }
        assert sink.startswith(os.path.join(tmp, ".jackal", "logs")), sink;
        assert sink.endswith(".jsonl"), sink;
        assert os.path.exists(sink), sink;
        recs = read_log(sink);
        assert len(recs) == 1, recs;
        assert recs[0]["level"] == "warn", recs[0];
    } finally {
        os.chdir(cwd);
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "level threshold filters lower-severity records" {
    tmp = tempfile.mkdtemp(prefix="jackal-log-level-");
    try {
        sink = os.path.join(tmp, "l.jsonl");
        env_snapshot = _set_env({"JACKAL_LOG": sink, "JACKAL_LOG_LEVEL": "warn"});
        try {
            log_debug("x", "debug line");
            log_info("x", "info line");
            log_warn("x", "warn line");
        } finally {
            _restore_env(env_snapshot);
        }
        recs = read_log(sink);
        assert len(recs) == 1, recs;
        assert recs[0]["level"] == "warn", recs[0];
    } finally {
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "unknown level names do not disable or crash logging" {
    tmp = tempfile.mkdtemp(prefix="jackal-log-badlevel-");
    try {
        sink = os.path.join(tmp, "l.jsonl");
        env_snapshot = _set_env({"JACKAL_LOG": sink, "JACKAL_LOG_LEVEL": "chatty"});
        wrote: bool = False;
        try {
            # Unknown threshold falls back to info; unknown record level -> info.
            wrote = log_event("nonsense", "x", "kept");
        } finally {
            _restore_env(env_snapshot);
        }
        assert wrote is True;
        recs = read_log(sink);
        assert len(recs) == 1 and recs[0]["level"] == "info", recs;
    } finally {
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "unserializable payloads are projected, not raised" {
    fields = {
        "obj": _Weird(),
        "blob": b"\x00\x01",
        "nested": {"a": [1, 2, {"b": _Weird()}]},
        "huge": "z" * (MAX_STRING_LEN + 50),
        "many": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22],
    };
    proj: dict[str, any] = safe_fields(fields) as dict[str, any];
    assert isinstance(proj, dict), proj;
    assert proj["obj"] == "<weird object>", proj["obj"];
    assert isinstance(proj["blob"], str), proj["blob"];
    huge: str = proj["huge"] as str;
    assert huge.endswith("..."), huge;
    assert len(huge) <= MAX_STRING_LEN + 3, len(huge);
    assert proj["many"][-1] == "...", proj["many"];
    # The whole write path must also survive it.
    tmp = tempfile.mkdtemp(prefix="jackal-log-weird-");
    try {
        sink = os.path.join(tmp, "w.jsonl");
        env_snapshot = _set_env({"JACKAL_LOG": sink, "JACKAL_LOG_LEVEL": "info"});
        wrote: bool = False;
        try {
            wrote = log_info("x", "weird payload", fields);
        } finally {
            _restore_env(env_snapshot);
        }
        assert wrote;
        assert len(read_log(sink)) == 1;
    } finally {
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "an unusable sink path is a no-op, not an exception" {
    tmp = tempfile.mkdtemp(prefix="jackal-log-badsink-");
    try {
        blocker = os.path.join(tmp, "blocker");
        fh: io.FileIO = io.FileIO(blocker, "wb");
        fh.write(b"not a directory");
        fh.close();
        # Parent "directory" is a regular file -> makedirs must fail.
        sink = os.path.join(blocker, "sub", "x.jsonl");
        env_snapshot = _set_env({"JACKAL_LOG": sink, "JACKAL_LOG_LEVEL": "debug"});
        wrote: bool = True;
        try {
            wrote = log_event("error", "x", "boom");
        } finally {
            _restore_env(env_snapshot);
        }
        assert wrote is False, wrote;
    } finally {
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "log_exception records type and message without Python traceback" {
    tmp = tempfile.mkdtemp(prefix="jackal-log-exc-");
    try {
        sink = os.path.join(tmp, "e.jsonl");
        env_snapshot = _set_env({"JACKAL_LOG": sink, "JACKAL_LOG_LEVEL": "debug"});
        wrote: bool = False;
        try {
            try {
                raise ValueError("disk on fire");
            } except Exception as exc {
                log_exception("agent.checkpoints", exc, {"phase": "capture"});
            }
            # Outside an except block: no traceback field, still no raise.
            wrote = log_exception("x", None);
        } finally {
            _restore_env(env_snapshot);
        }
        assert wrote is True, wrote;
        recs = read_log(sink);
        assert len(recs) == 2, recs;
        rec = recs[0];
        assert rec["level"] == "error", rec;
        assert rec["fields"]["exception"] == "Exception", rec;
        assert rec["fields"]["detail"] == "disk on fire", rec;
        assert rec["fields"]["phase"] == "capture", rec;
        rec_fields: dict[str, any] = rec["fields"] as dict[str, any];
        assert not ("traceback" in rec_fields), rec;
        # The no-exception call still logs, without a traceback field.
        second_rec = recs[1];
        assert second_rec["level"] == "error", second_rec;
        second_fields: dict[str, any] = second_rec["fields"] as dict[str, any];
        assert not ("traceback" in second_fields), second_rec;
    } finally {
        shutil.rmtree(tmp, ignore_errors=True);
    }
}


test "read_log skips malformed lines and missing files" {
    tmp = tempfile.mkdtemp(prefix="jackal-log-read-");
    try {
        path = os.path.join(tmp, "m.jsonl");
        fh: io.FileIO = io.FileIO(path, "wb");
        fh.write(b"{\"ok\": 1}\nnot json\n\n[1,2,3]\n{\"ok\": 2}\n");
        fh.close();
        recs = read_log(path);
        assert len(recs) == 2, recs;
        assert recs[0]["ok"] == 1 and recs[1]["ok"] == 2, recs;
        assert read_log(os.path.join(tmp, "missing.jsonl")) == [];
    } finally {
        shutil.rmtree(tmp, ignore_errors=True);
    }
}
