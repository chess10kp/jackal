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
import from _subprocess_native { sp_read }
import from agent.session {
    cancel_active_turn,
    clear_history,
    drain_mcp_notices,
    get_history,
    get_mode,
    get_model,
    json_event,
    list_commands,
    mcp_prompt,
    mcp_resources,
    mcp_restart,
    mcp_restart_failed,
    mcp_status_lines,
    plugins,
    restore_history,
    restore_model,
    run_command,
    session_dispose,
    set_current_session_id,
    set_mode,
    set_model,
    set_thinking_level,
}
import from agent.session_lifecycle { session_boot_headless }
import from agent.session_turn { compact_now, run_turn }
import from agent.auth_env { hydrate_auth_environment, logout_provider }
import from agent.cli { parse_cli, user_argv, combine_prompt, CLI_USAGE, CLI_VERSION }
import from agent.modes { requires_approval, is_read_only_mode, read_only_mode_block_reason }
import from agent.sessions {
    list_sessions,
    latest_session_id,
    get_session_record,
    export_session,
    save_session,
    is_valid_session_id,
}

"""Read one stdin line through the native file-descriptor floor."""
def _read_stdin_line() -> str {
    data: bytes = b"";
    while True {
        byte: bytes = sp_read(0, 1);
        if not byte {
            return data.decode("utf-8");
        }
        data += byte;
        if byte[0] == 10 {
            return data.decode("utf-8");
        }
    }
}

"""Read the remaining stdin stream through the native file-descriptor floor."""
def _read_stdin_all() -> str {
    data: bytes = b"";
    while True {
        chunk: bytes = sp_read(0, 65536);
        if not chunk {
            return data.decode("utf-8");
        }
        data += chunk;
    }
}


def print_banner {
    print("jackal - all-Jac agent harness");
    print(f"model: {get_model()}   cwd: {os.getcwd()}");
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
        "  /logout PROV   remove a stored provider credential\n"
        "  /compact       summarize older history to free context\n"
        "  /mode [NAME]   show or set dev mode (normal|auto-accept|yolo|plan|ask)\n"
        "  /commands      list extension commands\n"
        "  /exit          quit"
    );
}


"""Handle a /command. Returns reply text, or None to exit, or '' for none."""
def handle_command(line: str) -> str | None {
    if line in ("/exit", "/quit") { return None; }
    if line == "/help" { print_help(); return ""; }
    if line in ("/clear", "/new") {
        clear_history();
        # Fresh id: the next save must not overwrite the previous transcript.
        set_current_session_id("");
        return "history cleared";
    }
    if line == "/mcp" {
        mcp_rows: list[str] = mcp_status_lines();
        if not mcp_rows { return "no mcp servers configured"; }
        return "mcp servers:\n" + "\n".join(mcp_rows);
    }
    if line.startswith("/mcp ") {
        rest = line[len("/mcp"):].strip();
        if rest == "restart" {
            return mcp_restart_failed();
        }
        if rest.startswith("restart ") {
            return mcp_restart(rest[len("restart "):].strip());
        }
        if rest == "resources" or rest.startswith("resources ") {
            sub: str = rest[len("resources"):].strip();
            if not sub {
                return mcp_resources("", "");
            }
            stoks: list[str] = sub.split(None, 1);
            s_uri: str = stoks[1] if len(stoks) > 1 else "";
            return mcp_resources(str(stoks[0]), s_uri);
        }
        toks: list[str] = rest.split(None, 2);
        if len(toks) >= 2 {
            args_json: str = toks[2] if len(toks) >= 3 else "";
            return mcp_prompt(str(toks[0]), str(toks[1]), args_json);
        }
        return "usage: /mcp [restart [NAME] | resources [SERVER [URI]] | SERVER PROMPT [JSON_ARGS]]";
    }
    if line == "/compact" { return compact_now(); }
    if line == "/abort" {
        return "turn aborted" if cancel_active_turn() else "no active turn";
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
        hist = get_history();
        has_content = False;
        for m in hist {
            if isinstance(m, dict) and str(m.get("role", "")) != "system" {
                has_content = True;
                break;
            }
        }
        if not has_content { return "nothing to export yet"; }
        # Export needs a saved record; persist the live transcript first.
        if not is_valid_session_id(str(plugins.session_id)) {
            set_current_session_id("");
        }
        try {
            meta = save_session(
                os.getcwd(), hist, session_id=plugins.session_id,
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
        cmds = list_commands();
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
    if line.startswith("/logout") {
        prov = line[len("/logout"):].strip();
        if not prov { return "usage: /logout PROVIDER"; }
        return logout_provider(prov);
    }
    if line == "/mode" { return "mode: " + get_mode(); }
    if line.startswith("/mode ") {
        want = line[len("/mode "):].strip();
        try {
            return "mode -> " + set_mode(want);
        } except ValueError as e {
            return str(e);
        }
    }
    if line.startswith("/model ") {
        name = line[len("/model "):].strip();
        if name { return "model -> " + set_model(name); }
        return "usage: /model NAME";
    }
    if line.startswith("/") {
        # Extension commands take precedence over the unknown-command error.
        parts = line[1:].split(None, 1);
        name = parts[0] if parts else "";
        args = parts[1].strip() if len(parts) > 1 else "";
        if name and name in list_commands() {
            return run_command(name, args);
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
    restore_history(msgs as list);
    set_current_session_id(sid);
    rec_model: any = rec.get("model");
    reply: str = "resumed " + sid + " (" + str(len(msgs)) + " messages)";
    if isinstance(rec_model, str) and rec_model and rec_model != get_model() {
        reply += "\nmodel -> " + restore_model(rec_model);
    }
    return reply;
}


"""Mode-policy tool approver for headless frontends. `ask(name, args)`
answers "confirm" verdicts; ask=None (non-interactive) denies them with a
hint, so `-p` never runs a confirm-gated tool silently."""
def _approval_policy(name: str, args: dict[str, any]) -> str {
    cmd: str = "";
    if isinstance(args, dict) { cmd = str(args.get("cmd", "")); }
    mode: str = get_mode();
    policy: str = requires_approval(mode, name, cmd);
    if policy == "auto" { return "allow"; }
    if policy == "blocked" {
        if is_read_only_mode(mode) {
            return read_only_mode_block_reason(name, mode);
        }
        return "blocked in " + mode + " mode";
    }
    return "";
}


def _deny_approve(name: str, args: dict[str, any]) -> any {
    verdict: str = _approval_policy(name, args);
    if verdict == "allow" { return True; }
    if verdict { return verdict; }
    mode: str = get_mode();
    return (
        "tool \"" + name + "\" needs approval in " + mode
        + " mode; rerun with --mode auto-accept or --mode yolo"
    );
}


def _term_approve(name: str, args: dict[str, any]) -> any {
    verdict: str = _approval_policy(name, args);
    if verdict == "allow" { return True; }
    if verdict { return verdict; }
    return True if term_ask(name, args) else "denied by user";
}


def _json_approve(name: str, args: dict[str, any]) -> any {
    verdict: str = _approval_policy(name, args);
    if verdict == "allow" { return True; }
    if verdict { return verdict; }
    return True if json_ask(name, args) else "denied by user";
}


obj _PrintState {
    has format: str = "text",
        errors: list[str] = [],
        tools: int = 0,
        secs: float = 0.0;
}

glob _print_state: _PrintState | None = None;


def _print_event(kind: str, data: dict[str, any]) {
    state: _PrintState | None = _print_state;
    if state is None { return; }
    if kind == "error" { state.errors.append(str(data.get("message", ""))); }
    if kind == "tool_call" { state.tools += 1; }
    if kind == "turn_end" { state.secs = data.get("secs", 0.0) as float; }
    if state.format == "stream-json" {
        json_event(kind, data);
    } elif kind == "error" {
        sys.stderr.write("[error] " + str(data.get("message", "")) + "\n");
        sys.stderr.flush();
    }
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


"""JSONL approval round-trip: after react_loop's approval_request event, read stdin until an
{"type": "approval", "approved": bool} line arrives (EOF denies). Other
requests are rejected while the turn is blocked on the decision."""
def json_ask(name: str, args: dict[str, any]) -> bool {
    # react_loop already emitted approval_request on the event stream.
    while True {
        raw: str = _read_stdin_line();
        if not raw { return False; }
        text_in: str = str(raw).strip();
        if not text_in { continue; }
        try {
            parsed: any = json.loads(text_in);
        } except ValueError {
            json_event("error", {"message": "bad json: " + text_in[:80]});
            continue;
        }
        if not isinstance(parsed, dict) { continue; }
        req: dict[str, any] = parsed as dict[str, any];
        if str(req.get("type", "")) == "approval" {
            return bool(req.get("approved", False));
        }
        json_event("error", {"message": "awaiting approval decision"});
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
        result = set_model(model_name);
        if result != model_name { return result; }
    }
    if opts["thinking"] { set_thinking_level(str(opts["thinking"])); }
    if opts["mode"] { set_mode(str(opts["mode"])); }
    return "";
}


"""One-shot run (-p): execute `prompt`, write the answer per output_format,
return the process exit code (0 ok, 1 error)."""
def run_print(prompt: str, opts: dict[str, any]) -> int {
    fmt: str = str(opts["output_format"]);
    state = _PrintState(format=fmt);
    _print_state = state;
    max_turns: int = int(opts["max_turns"]) if opts["max_turns"] else 30;
    answer: str = "";
    try {
        answer = run_turn(
            prompt, _print_event, approve=_deny_approve, max_iters=max_turns,
        );
    } except KeyboardInterrupt {
        state.errors.append("interrupted");
    } except Exception as e {
        state.errors.append(str(e));
        sys.stderr.write("[error] " + str(e) + "\n");
    }
    _print_state = None;
    is_error: bool = not answer and len(state.errors) > 0;
    if fmt == "text" {
        if answer {
            sys.stdout.write(answer + ("" if answer.endswith("\n") else "\n"));
            sys.stdout.flush();
        }
    } else {
        json_event("result", {
            "result": answer,
            "is_error": is_error,
            "errors": state.errors,
            "session_id": str(plugins.session_id),
            "model": get_model(),
            "num_tools": state.tools,
            "duration_s": state.secs,
        });
    }
    return 1 if is_error else 0;
}


with entry:__main__ {
    # Pi lifecycle: boot loads .jackal/extensions.json and warms the Node
    # sidecar without blocking the first frame; run_turn awaits extension
    # readiness before the first model request.
    opts: dict[str, any] = parse_cli(user_argv(list(sys.argv)));
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
        if not os.isatty(0) { piped = _read_stdin_all(); }
        prompt = combine_prompt(prompt, piped);
        if not prompt {
            sys.stderr.write("jackal: -p needs a prompt (argument or stdin)\n");
            sys.exit(2);
        }
    }
    hydrate_auth_environment();
    session_boot_headless();
    opt_err: str = apply_cli_options(opts);
    if opt_err {
        sys.stderr.write("jackal: " + opt_err + "\n");
        session_dispose();
        sys.exit(1);
    }
    if print_mode {
        code: int = 1;
        try {
            code = run_print(prompt, opts);
        } finally {
            session_dispose();
        }
        sys.exit(code);
    }
    json_mode: bool = bool(opts["json"]);
    if json_mode {
        json_event("session_ready", {"model": get_model(), "cwd": os.getcwd()});
    } else {
        print_banner();
        if prompt {
            print("\n> " + prompt);
            try {
                run_turn(prompt, approve=_term_approve);
            } except KeyboardInterrupt {
                print("\n[interrupted]");
            }
        }
    }
    ended = False;
    try {
        while True {
            # Surface queued MCP notices (import/death/restart) each input
            # cycle — the TUI drains these per tick; the line/JSONL loops
            # per iteration. Also pumps death detection + list_changed.
            for note in drain_mcp_notices() {
                if json_mode {
                    json_event("notice", {"text": str(note)});
                } else {
                    print("[mcp] " + str(note));
                }
            }
            if json_mode {
                raw: str = _read_stdin_line();
                if not raw { break; }
                raw_line: any = raw;
                text_in: str = str(raw_line).strip();
                if not text_in { continue; }
                try {
                    parsed: any = json.loads(text_in);
                } except ValueError {
                    json_event("error", {"message": "bad json: " + text_in[:80]});
                    continue;
                }
                if not isinstance(parsed, dict) {
                    json_event("error", {"message": "request must be a JSON object"});
                    continue;
                }
                req: dict[str, any] = parsed as dict[str, any];
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
                    if json_mode { json_event("session_end", {}); ended = True; }
                    break;
                }
                if reply {
                    if json_mode { json_event("info", {"text": reply}); }
                    else { print(reply); }
                }
                continue;
            }
            try {
                if json_mode {
                    run_turn(text, json_event, approve=_json_approve);
                } else {
                    run_turn(text, approve=_term_approve);
                }
            } except KeyboardInterrupt {
                if json_mode { json_event("error", {"message": "interrupted"}); }
                else { print("\n[interrupted]"); }
            }
        }
    } finally {
        # Every exit path (EOF, /exit, fatal error) shuts extensions down:
        # session_shutdown hook fires, sidecar is disposed.
        session_dispose();
    }
    if json_mode {
        if not ended { json_event("session_end", {}); }
    } else { print("bye."); }
}
