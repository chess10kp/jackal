# Testing Jackal

Tests run on GitHub Actions (`.github/workflows/app-tests.yml`); the dev box is
compute-constrained, so push and read CI rather than running whole suites
locally.

## Layers

| Layer | Where | What it proves |
|---|---|---|
| Unit | `app/**/<mod>.test.jac` | One module, merged with `<mod>.jac` by stem (symbols visible without imports) |
| E2E headless | `app/e2e/{print_mode,json_protocol,repl}.test.jac` | The real `main.jac` process: flags, exit codes, output formats, approvals, sessions |
| TUI (in-process) | `app/tui/harness.test.jac` | The real LiveShell rendering into the Jac `EmulatedTerminal`; the test steps the host loop and asserts on the exact screen |
| E2E TUI (PTY) | `app/e2e/tui.test.jac` | `../jac run tui/shell.jac` as a real process under a pseudo-terminal: boot, terminal restore |

Every `*.test.jac` needs a same-stem `*.jac` module (the runner imports it);
e2e suites use tiny modules that only import the harness.

## Placement and test annexes

`app/jac.toml` pins modules to a codespace. A pin of `"x" = "native"` is
*hard*: `jac build` refuses to demote that module at seal time. Two rules
follow, and both are checked without a compiler build:

1. A hard-pinned module (and its `.impl.jac` / `.test.jac` annexes) must not
   call a server-placed module with anything but C-ABI values. Native calling
   into server code is `E5093` (`Type 'UiSession' ... cannot cross the
   native->server call boundary`).
2. The seal folds `<mod>.impl.jac` and `<mod>.test.jac` into `<mod>`'s unit
   (`NativeUnitRegistry._module_files_and_imports`). So a test-only import of
   a server module still fails the *module's* hard pin. Keep such cases in the
   server-placed owner's annex instead — e.g. the shell/topology assertions
   live in `app/ui/screen.test.jac`, not `app/ui/markup.test.jac`, because
   `ui.markup` is native and `ui.screen` is server.

`scripts/seal-pin-guard.mjs` enforces rule 1 statically (it reads the pins,
the annexes and the import graph; `CALLED` means an imported server name has a
call site). Reviewed exceptions live in `scripts/seal-pin-allowlist.txt`; an
entry that stops crossing is reported XPASS so the list cannot rot. Run it
directly or rely on the `seal-pins` CI job.

```bash
node scripts/seal-pin-guard.mjs            # fail on unlisted crossings
node scripts/seal-pin-guard.mjs --strict   # also fail on unused imports
```


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
  `wait_exit()`, `close()`. Output is replayed into the same Jac
  `EmulatedTerminal` the in-process harness uses; assert on visible text.

Always pass `sb.explain(r)` (run output + model calls) / rely on `wait_for`'s dump as the assertion
message — CI logs are the only debugger.

## Emulated terminal TUI harness (`app/tui/harness.jac`)

The Pi approach: render into a real terminal emulator, read back what a user
would see. `ui/emulated_terminal.jac` implements cursor addressing, erase,
scroll regions, wrapping, wide chars, and SGR behind the `Terminal` interface;
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

Three things to know before reading a run (learned 2026-11-01):

- **Reported counts are not the file's test count.** `jac test <suite>` also
  runs the tests registered by every module it imports, because importing a
  module pulls its `.test.jac` annex (jaseci-labs/jac#10493). A suite with 5
  tests can report 328. Read the `FAILED ...::<name>` lines, not the totals.
- **Do not run two suites against the same tree at once.** Two concurrent
  `jac test` processes on one checkout produced bare `rc=134` aborts with no
  output that never reproduced serially. Treat a no-output SIGABRT as
  contention until a solo re-run reproduces it.
- **Timeouts are portable.** Where coreutils `timeout` is missing (stock
  macOS) the runner puts the suite in its own process group and kills the
  group at `TIMEOUT` (default 600 s), reporting `TIMEOUT(143)`; servers and
  subprocesses die with it. On bash 3.2 the runner is sequential — there is no
  `wait -n` — so a 75-suite pass takes 2-4 h there.

## Debugging a failing suite

Swallowed `except` blocks still talk, but only when asked:

```bash
JACKAL_LOG=1 JACKAL_LOG_LEVEL=debug ./jac test agent/checkpoints.test.jac
# one JSON object per line in <cwd>/.jackal/logs/<date>-<pid>.jsonl
```

`JACKAL_LOG=<path>` writes to one explicit sink instead (tests use this);
unset or `JACKAL_LOG=0` is off. Records carry `ts level source msg pid` and
optional `fields` (tool name, path, exception type/detail/traceback). The
sink is shared by `agent/logging.jac` callers — checkpoint capture misses,
store read failures, and tool-handler exceptions land there rather than
disappearing.

## Quarantine

`scripts/test-quarantine.txt` lists known-failing suites, each with a reason.
They report XFAIL and don't fail CI; new failures do. A quarantined suite that
passes is reported XPASS in the job summary — delete its line. Never
quarantine a failure you introduced.

## Native seal (placement gate)

The full gate is `cd app && ../jac build`. Two things to check before believing
a seal result:

1. **The kernel is current.** `../jac native status` prints an "in use" column;
   `floor: the bytecode compiler` with `stale: ...` in "why" means the run is
   on the bytecode floor, not the native kernel. Wall sets differ between the
   two. `../jac native build kernel` (a Zig 0.16.0 host with the shared LLVM
   slice) fixes it.
2. **Read the log, not the exit code.** The seal prints hundreds of demotions;
   `scripts/seal-report.mjs` reduces them to hard walls, the source files the
   diagnostics actually point at, erased fields, soft module demotions, and the
   abort's E-code:

   ```bash
   (cd app && ../jac build > /tmp/seal.log 2>&1 || true)
   node scripts/seal-report.mjs /tmp/seal.log
   ```

   A hard wall is a module pinned `native` that did not lower. Soft demotions
   are allowed but each one is distance from N6 (the all-native goal).

