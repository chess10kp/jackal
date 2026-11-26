impl print_banner {
    print("jackal - all-Jac agent harness");
    print(f"model: {_session.get_model()}   cwd: {os.getcwd()}");
    print("/help for commands, /exit to quit");
}

impl print_help {
    print(
        "commands:\n"
            "  /help          this help\n"
            "  /model NAME    switch model (e.g. openrouter/anthropic/claude-sonnet-5)\n"
            "  /clear         clear conversation history\n"
            "  /abort         cancel the active turn (streaming or tool)\n"
            "  /sessions      list saved sessions\n"
            "  /resume [ID]   load a session transcript (default: latest)\n"
            "  /export [PATH] write the current transcript as markdown\n"
            "  /logout PROV   remove a stored provider credential\n"
            "  /compact       summarize older history to free context\n"
            "  /mode [NAME]   show or set dev mode (normal|auto-accept|yolo|plan|ask)\n"
            "  /commands      list extension commands\n"
            "  /exit          quit",
    );
}

impl handle_command(line: str) -> str | None {
    if line in ("/exit", "/quit") {
        return None;
    }
    if line == "/help" {
        print_help();
        return "";
    }
    if line in ("/clear", "/new") {
        _session.clear_history();
        _session.set_current_session_id("");
        return "history cleared";
    }
    if line == "/mcp" {
        mcp_rows: list[str] = _session.mcp_status_lines();
        if not mcp_rows {
            return "no mcp servers configured";
        }
        return "mcp servers:\n" + "\n".join(mcp_rows);
    }
    if line.startswith("/mcp ") {
        rest = line[len("/mcp"):].strip();
        if rest == "restart" {
            return _session.mcp_restart_failed();
        }
        if rest.startswith("restart ") {
            return _session.mcp_restart(rest[len("restart "):].strip());
        }
        if rest == "resources" or rest.startswith("resources ") {
            sub: str = rest[len("resources"):].strip();
            if not sub {
                return _session.mcp_resources("", "");
            }
            stoks: list[str] = sub.split(None, 1);
            s_uri: str = stoks[1] if len(stoks) > 1 else "";
            return _session.mcp_resources(str(stoks[0]), s_uri);
        }
        toks: list[str] = rest.split(None, 2);
        if len(toks) >= 2 {
            args_json: str = toks[2] if len(toks) >= 3 else "";
            return _session.mcp_prompt(str(toks[0]), str(toks[1]), args_json);
        }
        return "usage: /mcp [restart [NAME] | resources [SERVER [URI]] | SERVER PROMPT [JSON_ARGS]]";
    }
    if line == "/compact" {
        return _session.compact_now();
    }
    if line == "/abort" {
        return "turn aborted" if _session.cancel_active_turn() else "no active turn";
    }
    if line == "/sessions" {
        rows = list_sessions(os.getcwd());
        if not rows {
            return "no saved sessions";
        }
        lines: list[str] = ["saved sessions:"];
        for row in rows[:20] {
            lines.append("  " + str(row.get("id", "")) + "  " + str(row.get("name", "")));
        }
        return "\n".join(lines);
    }
    if line.startswith("/resume") {
        return resume_session(line[len("/resume"):].strip());
    }
    if line.startswith("/export") {
        arg = line[len("/export"):].strip();
        path = arg or "jackal-transcript.md";
        hist = _session.get_history();
        has_content = False;
        for m in hist {
            if isinstance(m, dict) and str(m.get("role", "")) != "system" {
                has_content = True;
                break;
            }
        }
        if not has_content {
            return "nothing to export yet";
        }
        if not is_valid_session_id(str(_session.plugins.session_id)) {
            _session.set_current_session_id("");
        }
        try {
            meta = save_session(os.getcwd(), hist, session_id=_session.plugins.session_id);
        } except Exception as e {
            return "ERROR: could not save transcript: " + str(e);
        }
        if export_session(os.getcwd(), str(meta["id"]), path) {
            return "exported to " + path;
        }
        return "ERROR: could not write " + path;
    }
    if line == "/commands" {
        cmds = _session.list_commands();
        if not cmds {
            return "no extension commands loaded";
        }
        lines: list[str] = ["extension commands:"];
        for raw_name in sorted(cmds.keys()) {
            ent = cmds[raw_name];
            name = str(raw_name);
            desc = "";
            if isinstance(ent, dict) {
                got = ent.get("description", "");
                if isinstance(got, str) {
                    desc = got;
                }
            }
            if desc {
                lines.append("  /" + name + "  " + desc);
            } else {
                lines.append("  /" + name);
            }
        }
        return "\n".join(lines);
    }
    if line.startswith("/logout") {
        prov = line[len("/logout"):].strip();
        if not prov {
            return "usage: /logout PROVIDER";
        }
        return logout_provider(prov);
    }
    if line == "/mode" {
        return "mode: " + _session.get_mode();
    }
    if line.startswith("/mode ") {
        want = line[len("/mode "):].strip();
        try {
            return "mode -> " + _session.set_mode(want);
        } except ValueError as e {
            return str(e);
        }
    }
    if line.startswith("/model ") {
        name = line[len("/model "):].strip();
        if name {
            return "model -> " + _session.set_model(name);
        }
        return "usage: /model NAME";
    }
    if line.startswith("/") {
        parts = line[1:].split(None, 1);
        name = parts[0] if parts else "";
        args = parts[1].strip() if len(parts) > 1 else "";
        if name and name in _session.list_commands() {
            return _session.run_command(name, args);
        }
        hint = " (/commands for extension commands)";
        return "unknown command: " + line + " (/help for list)" + hint;
    }
    return "";
}

impl resume_session(sid: str) -> str {
    if not sid {
        got = latest_session_id(os.getcwd());
        if got is None {
            return "no saved sessions to resume";
        }
        sid = got;
    }
    rec: dict[str, any] | None = get_session_record(os.getcwd(), sid);
    if rec is None {
        return "unknown session: " + sid;
    }
    msgs: any = rec.get("messages", []);
    if not isinstance(msgs, list) or not msgs {
        return "session has no transcript: " + sid;
    }
    _session.restore_history(msgs as list[dict[str, any]]);
    _session.set_current_session_id(sid);
    rec_model: any = rec.get("model");
    reply: str = "resumed " + sid + " (" + str(len(msgs)) + " messages)";
    if isinstance(rec_model, str) and rec_model and rec_model != _session.get_model() {
        reply += "\nmodel -> " + _session.restore_model(rec_model);
    }
    return reply;
}

impl make_approver(ask: any) -> any {
    def approve(name: str, args: dict[str, any]) -> any {
        cmd: str = "";
        if isinstance(args, dict) {
            cmd = str(args.get("cmd", ""));
        }
        mode: str = _session.get_mode();
        policy: str = requires_approval(mode, name, cmd);
        if policy == "auto" {
            return True;
        }
        if policy == "blocked" {
            if is_read_only_mode(mode) {
                return read_only_mode_block_reason(name, mode);
            }
            return "blocked in " + mode + " mode";
        }
        if ask is None {
            return (
                "tool \""
                + name
                + "\" needs approval in "
                + mode
                + " mode; rerun with --mode auto-accept or --mode yolo"
            );
        }
        if ask(name, args) {
            return True;
        }
        return "denied by user";
    }
    return approve;
}

impl _args_preview(args: dict[str, any]) -> str {
    try {
        return json.dumps(args)[:400];
    } except Exception {
        return str(args)[:400];
    }
}

impl term_ask(name: str, args: dict[str, any]) -> bool {
    print("\n  ? " + name + " " + _args_preview(args));
    try {
        got = input("  approve? [y/N] ").strip().lower();
    } except EOFError {
        return False;
    } except KeyboardInterrupt {
        return False;
    }
    return got in ("y", "yes");
}

impl json_ask(name: str, args: dict[str, any]) -> bool {
    while True {
        raw = sys.stdin.readline();
        if not raw {
            return False;
        }
        text_in: str = str(raw).strip();
        if not text_in {
            continue;
        }
        try {
            req: any = json.loads(text_in);
        } except ValueError {
            _session.json_event("error", {"message": "bad json: " + text_in[:80]});
            continue;
        }
        if isinstance(req, dict) and str(req.get("type", "")) == "approval" {
            return bool(req.get("approved", False));
        }
        _session.json_event("error", {"message": "awaiting approval decision"});
    }
    return False;
}

impl apply_cli_options(opts: dict[str, any]) -> str {
    if opts["continue"] or opts["resume"] {
        got = resume_session(str(opts["resume"]));
        if not got.startswith("resumed") {
            return got;
        }
    }
    model_name: str = str(opts["model"]);
    if model_name {
        result = _session.set_model(model_name);
        if result != model_name {
            return result;
        }
    }
    if opts["thinking"] {
        _session.set_thinking_level(str(opts["thinking"]));
    }
    if opts["mode"] {
        _session.set_mode(str(opts["mode"]));
    }
    return "";
}

impl run_print(prompt: str, opts: dict[str, any]) -> int {
    fmt: str = str(opts["output_format"]);
    errors: list[str] = [];
    stats: dict[str, any] = {"tools": 0, "secs": 0.0};

    def on_event(kind: str, data: dict[str, any]) {
        if kind == "error" {
            errors.append(str(data.get("message", "")));
        }
        if kind == "tool_call" {
            stats["tools"] = int(stats["tools"]) + 1;
        }
        if kind == "turn_end" {
            stats["secs"] = data.get("secs", 0.0);
        }
        if fmt == "stream-json" {
            _session.json_event(kind, data);
        } elif kind == "error" {
            sys.stderr.write("[error] " + str(data.get("message", "")) + "\n");
            sys.stderr.flush();
        }
    }
    max_turns: int = int(opts["max_turns"]) if opts["max_turns"] else 30;
    answer: str = "";
    try {
        answer = _session.run_turn(
            prompt, on_event, approve=make_approver(None), max_iters=max_turns
        );
    } except KeyboardInterrupt {
        errors.append("interrupted");
    } except Exception as e {
        errors.append(str(e));
        sys.stderr.write("[error] " + str(e) + "\n");
    }
    is_error: bool = not answer and len(errors) > 0;
    if fmt == "text" {
        if answer {
            sys.stdout.write(answer + ("" if answer.endswith("\n") else "\n"));
            sys.stdout.flush();
        }
    } else {
        _session.json_event(
            "result",
            {
                "result": answer,
                "is_error": is_error,
                "errors": errors,
                "session_id": str(_session.plugins.session_id),
                "model": _session.get_model(),
                "num_tools": stats["tools"],
                "duration_s": stats["secs"],
            },
        );
    }
    return 1 if is_error else 0;
}
