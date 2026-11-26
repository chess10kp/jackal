impl get_history -> list[dict[str, any]] {
    return list(history);
}

impl restore_history(msgs: list[dict[str, any]]) {
    history.clear();
    for m in msgs {
        if isinstance(m, dict) {
            history.append(dict(m));
        }
    }
}

impl set_current_session_id(sid: str) {
    plugins.session_id = sid or new_session_id();
}

impl cancel_active_turn -> bool {
    c = plugins.active_cancel;
    if c is not None and not c.cancelled {
        c.cancelled = True;
        return True;
    }
    return False;
}

impl list_commands -> dict[str, any] {
    b = plugins.bridge;
    if b is not None {
        plugins.commands = dict((b as PluginBridge).commands);
    }
    return dict(plugins.commands);
}

impl run_command(name: str, args: str = "") -> str {
    bridge = plugins.bridge;
    if bridge is None {
        return f"ERROR: no plugin host running (command /{name} unavailable)";
    }
    res: dict[str, any] = invoke_command(bridge as PluginBridge, name, args);
    _apply_pending_model_requests();
    lines: list[str] = [];
    for note in res.get("notifications", []) or [] {
        lines.append(str(note));
    }
    if res.get("ok") {
        result_s = str(res.get("result", ""));
        if result_s {
            lines.append(result_s);
        }
    } else {
        lines.append("ERROR: " + str(res.get("error", "command failed")));
    }
    return "\n".join(lines);
}

impl run_extension_shortcut(key: str) -> str {
    bridge = plugins.bridge;
    if bridge is None {
        return f"ERROR: no plugin host running (shortcut {key} unavailable)";
    }
    res: dict[str, any] = invoke_shortcut(bridge as PluginBridge, key);
    _apply_pending_model_requests();
    lines: list[str] = [];
    for note in res.get("notifications", []) or [] {
        lines.append(str(note));
    }
    if res.get("ok") {
        result_s = str(res.get("result", ""));
        if result_s {
            lines.append(result_s);
        }
    } else {
        lines.append("ERROR: " + str(res.get("error", "shortcut failed")));
    }
    return "\n".join(lines);
}

impl list_extension_shortcuts -> dict[str, any] {
    return list_shortcuts(plugins.bridge);
}

impl list_extension_labels -> dict[str, any] {
    return list_labels(plugins.bridge);
}

impl json_event(kind: str, data: dict[str, any]) {
    line = json.dumps({"type": kind, **data});
    out: any = sys.stdout;
    out.write(line + "\n");
    out.flush();
}
