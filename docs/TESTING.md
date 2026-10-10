# Testing Jackal

Tests run on GitHub Actions (`.github/workflows/app-tests.yml`); the dev box is
compute-constrained, so push and read CI rather than running whole suites
locally.

## Layers

| Layer | Where | What it proves |
|---|---|---|
| Unit | `app/**/<mod>.test.jac` | One module, merged with `<mod>.jac` by stem (symbols visible without imports) |
| E2E headless | `app/e2e/{print_mode,json_protocol,repl}.test.jac` | The real `main.jac` process: flags, exit codes, output formats, approvals, sessions |
| E2E TUI | `app/e2e/tui.test.jac` | `tui/shell.jac` under a real PTY: first frame, streaming, approval modal, slash commands, terminal restore |

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
  `wait_exit()`, `close()`. Output is replayed into `e2e/screen.jac`, a small
  ANSI screen emulator; assert on visible text.

Always pass `r.describe()` / rely on `wait_for`'s dump as the assertion
message — CI logs are the only debugger.

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
