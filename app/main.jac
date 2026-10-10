"""Jackal - all-Jac coding agent harness.

Three frontends, one session:
  term:  line REPL (default)
  json:  `--json` — JSONL protocol on stdio for UI clients (one JSON object
         per line; see json_event in agent/session.jac for the event set)
  print: `-p PROMPT` — one-shot run; answer on stdout (or a JSON result with
         --output-format json|stream-json), exit code 1 on failure

Flags are parsed by agent/cli.jac (`--help` for the list).
"""

import sys;
import os;
import json;
import agent.session as _session;
import from agent.session { clear_history }
import from agent.cli { parse_cli, combine_prompt, CLI_USAGE, CLI_VERSION }
import from agent.modes { requires_approval, is_read_only_mode, read_only_mode_block_reason }
import from agent.sessions {
    list_sessions,
    latest_session_id,
    get_session_record,
    export_session,
    save_session,
    is_valid_session_id,
}


def print_banner {
    print("jackal - all-Jac agent harness");
    print(f"model: {_session.get_model()}   cwd: {os.getcwd()}");
    print("/help for commands, /exit to quit");
}


def print_help {
    print(
        "commands:\n"
        "  /help          this help\n"
        "  /model NAME    switch model (e.g. openrouter/anthropic/claude-sonnet-5)\n"
        "  /clear         clear conversation history\n"
        "  /abort         cancel the active turn (streaming or tool)\n"
        "  /sessions      list saved sessions\n"
        "  /resume [ID]   load a session transcript (default: latest)\n"
        "  /export [PATH] write the current transcript as markdown\n"
        "  /mode [NAME]   show or set dev mode (normal|auto-accept|yolo|plan|ask)\n"
        "  /commands      list extension commands\n"
        "  /exit          quit"
    );
}


"""Handle a /command. Returns reply text, or None to exit, or '' for none."""
def handle_command(line: str) -> str | None {
    if line in ("/exit", "/quit") { return None; }
    if line == "/help" { print_help(); return ""; }
    if line == "/clear" { _session.clear_history(); return "history cleared"; }
    if line == "/abort" {
        return "turn aborted" if _session.cancel_active_turn() else "no active turn";
    }
    if line == "/sessions" {
        rows = list_sessions(os.getcwd());
        if not rows { return "no saved sessions"; }
        lines: list[str] = ["saved sessions:"];
        for row in rows[:20] {
            lines.append(
                "  " + str(row.get("id", "")) + "  "
                + str(row.get("name", ""))
            );
        }
        return "\n".join(lines);
    }
    if line.startswith("/resume") {
        return resume_session(line[len("/resume"):].strip());
    }
    if line.startswith("/export") {
        arg = line[len("/export"):].strip();
        path = arg if arg else "jackal-transcript.md";
        hist = _session.get_history();
        has_content = False;
        for m in hist {
            if isinstance(m, dict) and str(m.get("role", "")) != "system" {
                has_content = True;
                break;
            }
        }
        if not has_content { return "nothing to export yet"; }
        # Export needs a saved record; persist the live transcript first.
        if not is_valid_session_id(str(_session.plugins.session_id)) {
            _session.set_current_session_id("");
        }
        try {
            meta = save_session(
                os.getcwd(), hist, session_id=_session.plugins.session_id,
            );
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
        if not cmds { return "no extension commands loaded"; }
        lines: list[str] = ["extension commands:"];
        for raw_name in sorted(cmds.keys()) {
            ent = cmds[raw_name];
            name = str(raw_name);
            desc = "";
            if isinstance(ent, dict) {
                got = ent.get("description", "");
                if isinstance(got, str) { desc = got; }
            }
            if desc {
                lines.append("  /" + name + "  " + desc);
            } else {
                lines.append("  /" + name);
            }
        }
        return "\n".join(lines);
    }
    if line == "/mode" { return "mode: " + _session.get_mode(); }
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
        if name { return "model -> " + _session.set_model(name); }
        return "usage: /model NAME";
    }
    if line.startswith("/") {
        # Extension commands take precedence over the unknown-command error.
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


"""Load a saved session (latest when `sid` is empty) into the live history
and keep persisting under the same id. Returns a status line; failures start
with "unknown"/"no"/"session"."""
def resume_session(sid: str) -> str {
    if not sid {
        got = latest_session_id(os.getcwd());
        if got is None { return "no saved sessions to resume"; }
        sid = got;
    }
    rec: dict[str, any] | None = get_session_record(os.getcwd(), sid);
    if rec is None { return "unknown session: " + sid; }
    msgs: any = rec.get("messages", []);
    if not isinstance(msgs, list) or not msgs {
        return "session has no transcript: " + sid;
    }
    _session.restore_history(msgs as list);
    _session.set_current_session_id(sid);
    rec_model: any = rec.get("model");
    reply: str = "resumed " + sid + " (" + str(len(msgs)) + " messages)";
    if isinstance(rec_model, str) and rec_model and rec_model != _session.get_model() {
        reply += "\nmodel -> " + _session.restore_model(rec_model);
    }
    return reply;
}


"""Mode-policy tool approver for headless frontends. `ask(name, args)`
answers "confirm" verdicts; ask=None (non-interactive) denies them with a
hint, so `-p` never runs a confirm-gated tool silently."""
def make_approver(ask: any) -> any {
    def approve(name: str, args: dict[str, any]) -> any {
        cmd: str = "";
        if isinstance(args, dict) { cmd = str(args.get("cmd", "")); }
        mode: str = _session.get_mode();
        policy: str = requires_approval(mode, name, cmd);
        if policy == "auto" { return True; }
        if policy == "blocked" {
            if is_read_only_mode(mode) {
                return read_only_mode_block_reason(name, mode);
            }
            return "blocked in " + mode + " mode";
        }
        if ask is None {
            return (
                "tool \"" + name + "\" needs approval in " + mode
                + " mode; rerun with --mode auto-accept or --mode yolo"
            );
        }
        if ask(name, args) { return True; }
        return "denied by user";
    }
    return approve;
}


def _args_preview(args: dict[str, any]) -> str {
    try {
        return json.dumps(args)[:400];
    } except Exception {
        return str(args)[:400];
    }
}


"""Line-REPL approval prompt on the controlling terminal."""
def term_ask(name: str, args: dict[str, any]) -> bool {
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


"""JSONL approval round-trip: emit approval_request, then read stdin until an
{"type": "approval", "approved": bool} line arrives (EOF denies). Other
requests are rejected while the turn is blocked on the decision."""
def json_ask(name: str, args: dict[str, any]) -> bool {
    _session.json_event("approval_request", {"tool": name, "args": args});
    while True {
        raw = sys.stdin.readline();
        if not raw { return False; }
        text_in: str = str(raw).strip();
        if not text_in { continue; }
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


"""Apply --model/--thinking/--mode/--continue/--resume after boot. Returns
an error message, or "" on success."""
def apply_cli_options(opts: dict[str, any]) -> str {
    if opts["continue"] or opts["resume"] {
        got = resume_session(str(opts["resume"]));
        if not got.startswith("resumed") { return got; }
    }
    model_name: str = str(opts["model"]);
    if model_name {
        result = _session.set_model(model_name);
        if result != model_name { return result; }
    }
    if opts["thinking"] { _session.set_thinking_level(str(opts["thinking"])); }
    if opts["mode"] { _session.set_mode(str(opts["mode"])); }
    return "";
}


"""One-shot run (-p): execute `prompt`, write the answer per output_format,
return the process exit code (0 ok, 1 error)."""
def run_print(prompt: str, opts: dict[str, any]) -> int {
    fmt: str = str(opts["output_format"]);
    errors: list[str] = [];
    stats: dict[str, any] = {"tools": 0, "secs": 0.0};

    def on_event(kind: str, data: dict[str, any]) {
        if kind == "error" { errors.append(str(data.get("message", ""))); }
        if kind == "tool_call" { stats["tools"] = int(stats["tools"]) + 1; }
        if kind == "turn_end" { stats["secs"] = data.get("secs", 0.0); }
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
            prompt, on_event, approve=make_approver(None), max_iters=max_turns,
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
        _session.json_event("result", {
            "result": answer,
            "is_error": is_error,
            "errors": errors,
            "session_id": str(_session.plugins.session_id),
            "model": _session.get_model(),
            "num_tools": stats["tools"],
            "duration_s": stats["secs"],
        });
    }
    return 1 if is_error else 0;
}


with entry:__main__ {
    # Pi lifecycle: boot loads .jackal/extensions.json and warms the Node
    # sidecar without blocking the first frame; run_turn awaits extension
    # readiness before the first model request.
    opts: dict[str, any] = parse_cli(sys.argv[1:]);
    if opts["help"] { print(CLI_USAGE); sys.exit(0); }
    if opts["version"] { print("jackal " + CLI_VERSION); sys.exit(0); }
    if opts["error"] {
        sys.stderr.write("jackal: " + str(opts["error"]) + "\n" + CLI_USAGE + "\n");
        sys.exit(2);
    }
    print_mode: bool = bool(opts["print"]);
    prompt: str = str(opts["prompt"]);
    if print_mode {
        piped: str = "";
        if not sys.stdin.isatty() { piped = sys.stdin.read(); }
        prompt = combine_prompt(prompt, piped);
        if not prompt {
            sys.stderr.write("jackal: -p needs a prompt (argument or stdin)\n");
            sys.exit(2);
        }
    }
    _session.session_boot();
    opt_err: str = apply_cli_options(opts);
    if opt_err {
        sys.stderr.write("jackal: " + opt_err + "\n");
        _session.session_dispose();
        sys.exit(1);
    }
    if print_mode {
        code: int = 1;
        try {
            code = run_print(prompt, opts);
        } finally {
            _session.session_dispose();
        }
        sys.exit(code);
    }
    json_mode: bool = bool(opts["json"]);
    approver: any = make_approver(json_ask if json_mode else term_ask);
    if json_mode {
        _session.json_event("session_ready", {"model": _session.get_model(), "cwd": os.getcwd()});
    } else {
        print_banner();
        if prompt {
            print("\n> " + prompt);
            try {
                _session.run_turn(prompt, approve=approver);
            } except KeyboardInterrupt {
                print("\n[interrupted]");
            }
        }
    }
    ended = False;
    try {
        while True {
            if json_mode {
                raw = sys.stdin.readline();
                if not raw { break; }
                raw_line: any = raw;
                text_in: str = str(raw_line).strip();
                if not text_in { continue; }
                try {
                    req: any = json.loads(text_in);
                } except ValueError {
                    _session.json_event("error", {"message": "bad json: " + text_in[:80]});
                    continue;
                }
                text = str(req.get("text", ""));
                kind = str(req.get("type", "user"));
            } else {
                try {
                    text = input("\n> ").strip();
                } except EOFError {
                    print("");
                    break;
                } except KeyboardInterrupt {
                    print("");
                    continue;
                }
                if not text { continue; }
                kind = "command" if text.startswith("/") else "user";
            }
            if kind == "command" {
                reply = handle_command(text);
                if reply is None {
                    if json_mode { _session.json_event("session_end", {}); ended = True; }
                    break;
                }
                if reply {
                    if json_mode { _session.json_event("info", {"text": reply}); }
                    else { print(reply); }
                }
                continue;
            }
            try {
                if json_mode {
                    _session.run_turn(text, _session.json_event, approve=approver);
                } else {
                    _session.run_turn(text, approve=approver);
                }
            } except KeyboardInterrupt {
                if json_mode { _session.json_event("error", {"message": "interrupted"}); }
                else { print("\n[interrupted]"); }
            }
        }
    } finally {
        # Every exit path (EOF, /exit, fatal error) shuts extensions down:
        # session_shutdown hook fires, sidecar is disposed.
        _session.session_dispose();
    }
    if json_mode {
        if not ended { _session.json_event("session_end", {}); }
    } else { print("bye."); }
}
