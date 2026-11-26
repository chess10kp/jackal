import tempfile;
import shutil;

test "config defaults and override resolution" {
    d = resolve_auto_compact_config(None);
    assert d["enabled"] is True;
    assert d["thresholdPercent"] == 80;
    assert d["keepTail"] == 12;
    assert d["notify"] is True;
    assert d["strategy"] == "llm";
    off = resolve_auto_compact_config({"autoCompact": False});
    assert off["enabled"] is False;
    on = resolve_auto_compact_config({"autoCompact": True});
    assert on["enabled"] is True;
    part = resolve_auto_compact_config({"autoCompact": {"thresholdPercent": 65}});
    assert part["thresholdPercent"] == 65;
    assert part["enabled"] is True;
    assert part["keepTail"] == 12;
    mech = resolve_auto_compact_config({}, "mechanical");
    assert mech["strategy"] == "mechanical";
    bogus = resolve_auto_compact_config({}, "shrink");
    assert bogus["strategy"] == "llm";
}

test "should_auto_compact thresholds" {
    cfg_on = {"enabled": True, "thresholdPercent": 80};
    cfg_off = {"enabled": False, "thresholdPercent": 0};
    below = {"percent": 79};
    at = {"percent": 80};
    above = {"percent": 95};

    assert should_auto_compact(below, cfg_on) is False;
    assert should_auto_compact(at, cfg_on) is True;
    assert should_auto_compact(above, cfg_on) is True;
    assert should_auto_compact({"percent": 100}, cfg_off) is False;
}

test "usage estimation is char/4 with per-message overhead" {
    assert estimate_tokens("") == 0;
    assert estimate_tokens("12345678") == 2;
    assert estimate_tokens("12345") == 2;
    msgs: list[dict[str, any]] = [{"role": "user", "content": "abcdefgh"}];
    usage = compute_context_usage(msgs);
    assert usage["used"] == 6;
    assert usage["max"] == DEFAULT_CONTEXT_MAX;
    assert usage["percent"] == round((6 / DEFAULT_CONTEXT_MAX) * 100);
}

test "mechanical summary shape: wrapper, role prefixes, truncation" {
    msgs = [
        {"role": "user", "content": "hello"},
        {
            "role": "assistant",
            "content": [{"type": "text", "text": "hi"}, {"type": "toolCall", "name": "read"}],
        },
        {"content": "no role here"},
        {"role": "tool", "content": "x" * 400},
    ];
    s = build_mechanical_summary(msgs);
    lines = s.split("\n");
    assert lines[0] == "<context-summary>";
    assert lines[-1] == "</context-summary>";
    assert lines[1] == "Earlier conversation context (auto-compacted for space):";
    assert "[user] hello" in lines;
    assert "[unknown] no role here" in lines;
    joined = "\n".join(lines);
    assert "hi | [tool call: read]" in joined;
    long_line = "";
    for ln in lines {
        if ln.startswith("[tool]") {
            long_line = ln;
        }
    }
    body = long_line[len("[tool] "):];
    assert len(body) == 300;
    assert body.endswith("...");
}

test "llm summary prompt previews truncate at 200 and wrap summary guards empty" {
    msgs: list[dict[str, any]] = [{"role": "user", "content": "y" * 500}];
    p = build_llm_summary_prompt(msgs);
    plines = p.split("\n");
    assert plines[0].startswith("Summarize the following conversation context");
    last = plines[-1];
    assert len(last) == 207;
    assert last.endswith("...");
    assert len(last[7:]) == 200;

    assert wrap_compaction_summary("  ") == "";
    w = wrap_compaction_summary("brief facts");
    assert w.startswith("<conversation-summary>\nbrief facts\n</conversation-summary>");
}

test "project config also loads from .jackal/config.json" {
    tmp_dir = tempfile.mkdtemp(prefix="jackal-cfg-");
    try {
        os.makedirs(os.path.join(tmp_dir, ".jackal", "sessions"));
        fh = open(os.path.join(tmp_dir, ".jackal", "config.json"), "w");
        fh.write('{"compactStrategy": "llm"}');
        fh.close();
        sub = os.path.join(tmp_dir, "pkg");
        os.makedirs(sub);
        assert load_project_config(sub).get("compactStrategy") == "llm";
    } finally {
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
