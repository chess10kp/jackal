impl _path_abspath(p: str) -> str {
    return str(os.path.abspath(p));
}

impl _path_dirname(p: str) -> str {
    return str(os.path.dirname(p));
}

impl estimate_tokens(text: str) -> int {
    if not text {
        return 0;
    }
    return (len(text) + CHARS_PER_TOKEN - 1) // CHARS_PER_TOKEN;
}

impl _message_to_text(message: dict[str, any]) -> str {
    content: any = message.get("content");
    if isinstance(content, str) {
        return content;
    }
    if isinstance(content, list) {
        parts: list[str] = [];
        for part in content {
            if isinstance(part, str) {
                parts.append(part);
            } elif isinstance(part, dict) {
                if part.get("type") == "text" and part.get("text") {
                    parts.append(str(part.get("text")));
                } else {
                    parts.append(json.dumps(part));
                }
            } else {
                parts.append(str(part));
            }
        }
        return "\n".join(parts);
    }
    if content is not None {
        return json.dumps(content);
    }
    return "";
}

impl estimate_messages_tokens(messages: list[dict[str, any]]) -> int {
    total = 0;
    for msg in messages {
        if isinstance(msg, dict) {
            total += estimate_tokens(_message_to_text(msg));
            total += 4;
        }
    }
    return total;
}

impl compute_context_usage(
    messages: list[dict[str, any]], context_max_override: any = None
) -> dict[str, int] {
    used = estimate_messages_tokens(messages);
    max_tokens: int = DEFAULT_CONTEXT_MAX;
    if isinstance(context_max_override, int) and context_max_override > 0 {
        max_tokens = context_max_override;
    }
    percent = min(100, round((used / max_tokens) * 100));
    return {"used": used, "max": max_tokens, "percent": percent};
}

impl load_project_config(cwd: str) -> dict[str, any] {
    cur = _path_abspath(cwd);
    while True {
        cand = os.path.join(cur, ".jackal");
        if os.path.isdir(cand) {
            cand = os.path.join(cand, "config.json");
        }
        if os.path.isfile(cand) {
            try {
                with open(cand, "r", encoding="utf-8") as fh {
                    parsed = json.load(fh);
                }
                if isinstance(parsed, dict) {
                    return parsed;
                }
            } except Exception {
                return {};
            }
        }
        parent = _path_dirname(cur);
        if parent == cur {
            return {};
        }
        cur = parent;
    }
}

impl resolve_auto_compact_config(
    raw: dict[str, any] | None = None, compact_strategy: str = ""
) -> dict[str, any] {
    cfg: any = None;
    if raw is not None {
        cfg = raw.get("autoCompact");
    }
    if cfg is False {
        out = dict(DEFAULT_AUTO_COMPACT);
        out["enabled"] = False;
        return out;
    }
    if cfg is True {
        out = dict(DEFAULT_AUTO_COMPACT);
        out["enabled"] = True;
        return out;
    }
    merged = dict(DEFAULT_AUTO_COMPACT);
    if isinstance(cfg, dict) {
        merged.update(cfg as dict[str, any]);
    }
    if compact_strategy == "llm" or compact_strategy == "mechanical" {
        merged["strategy"] = compact_strategy;
    }
    return merged;
}

impl should_auto_compact(usage: dict[str, int], config: dict[str, any]) -> bool {
    if not config.get("enabled", True) {
        return False;
    }
    threshold: any = config.get("thresholdPercent", 80);
    pct: any = usage.get("percent", 0);
    return float(pct) >= float(threshold);
}

impl _extract_content_text(content: any) -> str {
    if isinstance(content, str) {
        return content;
    }
    if isinstance(content, list) {
        pieces: list[str] = [];
        for part in content {
            if isinstance(part, str) {
                pieces.append(part);
            } elif isinstance(part, dict) {
                if part.get("text") is not None {
                    pieces.append(str(part.get("text")));
                } elif part.get("type") == "toolCall" {
                    name: any = part.get("name");
                    label: str = str(name) if name is not None else "unknown";
                    pieces.append(f"[tool call: {label}]");
                }
            }
        }
        kept: list[str] = [];
        for p in pieces {
            if p {
                kept.append(p);
            }
        }
        return " | ".join(kept);
    }
    return "";
}

impl build_mechanical_summary(messages: list[dict[str, any]]) -> str {
    lines: list[str] = [
        "<context-summary>",
        "Earlier conversation context (auto-compacted for space):",
        "",
    ];
    for msg in messages {
        role: str = "unknown";
        text = "";
        if isinstance(msg, dict) {
            r: any = msg.get("role");
            if r is not None {
                role = str(r);
            }
            text = _extract_content_text(msg.get("content"));
        }
        if len(text) > 300 {
            text = text[0:297] + "...";
        }
        lines.append(f"[{role}] {text}");
    }
    lines.append("</context-summary>");
    return "\n".join(lines);
}

impl build_llm_summary_prompt(messages: list[dict[str, any]]) -> str {
    previews: list[str] = [];
    for msg in messages {
        role: str = "unknown";
        text = "";
        if isinstance(msg, dict) {
            r: any = msg.get("role");
            if r is not None {
                role = str(r);
            }
            text = _extract_content_text(msg.get("content"));
        }
        if len(text) > 200 {
            text = text[0:197] + "...";
        }
        previews.append(f"[{role}] {text}");
    }
    lines: list[str] = [
        "Summarize the following conversation context in 200 words or less.",
        "Preserve key facts: file paths, function/class names, error messages, decisions made, and any code patterns discussed.",
        "Do NOT include pleasantries or filler - only technical substance.",
        "",
    ];
    for p in previews {
        lines.append(p);
    }
    return "\n".join(lines);
}

impl wrap_compaction_summary(text: str) -> str {
    trimmed = text.strip();
    if not trimmed {
        return "";
    }
    return "\n".join([
        "<conversation-summary>",
        trimmed,
        "</conversation-summary>",
        "",
        "(The above is an automated summary of earlier conversation. Continue from the most recent message.)",
    ]);
}

impl summarize_for_compaction(
    messages: list[dict[str, any]], model_name: str, thinking: str = ""
) -> str | None {
    if not messages or not model_name {
        return None;
    }
    prompt = build_llm_summary_prompt(messages);
    try {
        transport = make_transport(model_name, thinking);
        if not transport.api_key {
            return None;
        }
        pieces: list[str] = [];
        for chunk in transport.stream([{"role": "user", "content": prompt}], []) {
            c: any = chunk.get("content");
            if isinstance(c, str) {
                pieces.append(c);
            }
            if chunk.get("error") is not None {
                return None;
            }
        }
        return wrap_compaction_summary("".join(pieces)) or None;
    } except Exception {
        return None;
    }
}
