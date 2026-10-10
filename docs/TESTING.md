# Testing Jackal

Tests run on GitHub Actions (`.github/workflows/app-tests.yml`); the dev box is
compute-constrained, so push and read CI rather than running whole suites
locally.

## Layers

| Layer | Where | What it proves |
|---|---|---|
| Unit | `app/**/<mod>.test.jac` | One module, merged with `<mod>.jac` by stem (symbols visible without imports) |
| E2E headless | `app/e2e/{print_mode,json_protocol,repl}.test.jac` | The real `main.jac` process: flags, exit codes, output formats, approvals, sessions |
| TUI (in-process) | `app/tui/harness.test.jac` | The real LiveShell rendering into `EmulatedTerminal` (pyte VT emulator — Pi's xterm-headless `VirtualTerminal` equivalent); the test steps the host loop and asserts on the exact screen |
| E2E TUI (PTY) | `app/e2e/tui.test.jac` | `jac run tui/shell.jac` as a real process under a pseudo-terminal: boot, terminal restore |

Every `*.test.jac` needs a same-stem `*.jac` module (the runner imports it);
e2e suites use tiny modules that only import the harness.

## The mock provider

Model id `mock` (also `mockllm`, `mock/*`) routes to `MockTransport` in
`app/agent/llm_transport.jac` — offline, keyless, deterministic.

- `JACKAL_MOCK_SCRIPT=steps.json` — a JSON list; each model call consumes one:
  - `{"text": "answer"}`
  - `{"text": "", "tool_calls": [{"name": "edit_file", "args": {...}}]}`
  - `{"error": "HTTP 500: boom"}`
  Unscripted (or exhausted) calls reply `mock: <last user message>`.
- `JACKAL_MOCK_LOG=calls.jsonl` — one line per call:
  `{"call", "messages", "last": {"role", "content"}, "tools": [...]}`.

Subagents and LLM compaction also go through the transport, so they consume
script steps too.

## E2E harness (`app/e2e/harness.jac`)

```jac
sb = make_sandbox({"notes.txt": "alpha\n"});   # isolated project/agent dir/HOME
try {
    sb.script([
        {"text": "", "tool_calls": [{"name": "edit_file", "args": {"path": "notes.txt", "old_text": "alpha", "new_text": "beta"}}]},
        {"text": "done"},
    ]);
    r = run_jackal(sb, ["-p", "--mode", "yolo", "rename"]);   # RunResult
    assert r.code == 0, r.describe();
    assert sb.read("notes.txt") == "beta\n";
    assert sb.calls()[1]["last"]["role"] == "tool";
} finally {
    sb.cleanup();
}
```

- `run_jackal(sb, args, stdin_text=..., env_extra=...)` → `RunResult` with
  `code`, `stdout`, `stderr`, `events()` (JSONL), `event_types()`, `describe()`.
- `jsonl(kind, text, extra)` builds `--json` protocol request lines.
- `spawn_tui(sb, cols, rows)` → `TuiSession`: `type_text`, `press("enter"|"esc"|"shift+tab"|...)`,
  `wait_for(text)` (fails with a screen dump), `screen_text()`, `raw_output()`,
  `wait_exit()`, `close()`. Output is replayed into the same pyte-backed
  `EmulatedTerminal` the in-process harness uses; assert on visible text.

Always pass `sb.explain(r)` (run output + model calls) / rely on `wait_for`'s dump as the assertion
message — CI logs are the only debugger.

## Emulated terminal TUI harness (`app/tui/harness.jac`)

The Pi approach: render into a real terminal emulator, read back what a user
would see. `ui/emulated_terminal.jac` wraps pyte (cursor addressing, erase,
scroll regions, wrapping, wide chars, SGR) behind the `Terminal` interface;
`tui/shell.jac` exposes `boot_tui(term)` / `tui_step(app)` / `shutdown_tui(app)`
so a test owns the host loop.

```jac
h = open_tui(files={"n.txt": "alpha\n"}, script=[...], mode="normal");
try {
    h.type_text("edit it");          # one char per loop tick
    h.press("enter");                # enter, esc, up, shift+tab, ctrl+c, ...
    h.wait_for("approve");           # steps until visible; fails with a framed screen dump
    h.press("y");
    h.wait_idle();                   # agent turn finished
    assert h.read("n.txt") == "beta\n";
    assert h.term.find("\u25c7 jackal") is not None;
    h.resize(50, 20);
} finally {
    h.close();                       # restores cwd/env, terminal modes
}
```

Read-back on `h.term`: `viewport()`, `scroll_buffer()`, `cursor()`,
`cell(row, col)` (char/fg/bg/bold/reverse…), `find(text)`, `line_with(text)`,
plus mode flags (`alternate_screen`, `bracketed_paste`, `cursor_visible`,
`title`). `h.dump()` gives the framed screen, cursor, phase and model calls.

## Running

```bash
scripts/test.sh                       # every suite, sequential
scripts/test.sh -j3 app/agent/        # a subtree in parallel
scripts/test.sh -k print_mode         # by suite-name keyword
scripts/test.sh --quarantine scripts/test-quarantine.txt
```

Per-suite logs land in `.testlogs/` (uploaded as CI artifacts
`testlogs-<shard>`; fetch with `gh run download <run-id>`). CI shards: `agent`,
`tui`, `ui`, `e2e`, `other`, plus a `jac check` job.

## Quarantine

`scripts/test-quarantine.txt` lists known-failing suites, each with a reason.
They report XFAIL and don't fail CI; new failures do. A quarantined suite that
passes is reported XPASS in the job summary — delete its line. Never
quarantine a failure you introduced.
