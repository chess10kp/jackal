# Jackal harness — implementation handoff

Written 2026-10-10 by the previous agent for the next one. Read this file
completely before touching code. It is meant to let you finish the work
without re-deriving anything. Where it says **DO**, do exactly that; where it
says **DECIDE**, follow the stated default unless the user says otherwise.

---

## 0. The goal

1. **Testing infra the agent can use to verify the harness by itself** (the
   user's words: "the harness itself needs good testing infra so that you can
   check it", "moreso what Pi has … modelling a real terminal"). Most of it is
   built (§3). What's left is **making CI green and trustworthy** (§5,
   Phase A–B).
2. **Then the harness should be feature-complete** as a daily-driver coding
   agent (Pi / Claude Code parity). The remaining feature work is in §5,
   Phase C–D.

User constraints (hard rules):
- **Never run test suites locally.** The box has no spare compute (14 GB RAM,
  heavy swap). Push and read GitHub Actions. Avoid running even `jac check` locally.
- Commit after each feature/bugfix. Push to `main` (that is the workflow here).
- Be brief with the user.
- `AGENTS.md` rules apply (no legacy `src/`, `templates/`, `tui/*.tsx`,
  `lib/jac/` edits; product work lives in `app/`).

---

## 1. Environment facts you would otherwise waste time on

### /tmp is a full tmpfs
`/tmp` (7.5 GB tmpfs) fills up because other Claude sessions write there.
When it is full, **every Bash call loses its output** ("Command output was
lost … ENOSPC"). Workaround used all session, and it still works:

```bash
cmd > /home/jac/.cc-out.txt 2>&1; true      # then Read /home/jac/.cc-out.txt
```

Write command output to a file under `/home/jac/` and read it with the Read
tool. Do NOT delete other sessions' dirs under `/tmp/claude-1000/`. Deleting
`/tmp/pytest-of-jac` is safe.

### Toolchain
- `jac` on PATH = jacup-managed **0.37.25** (`~/.local/share/jacup/bin/jac`).
  The `vendor/jac` subtree is gone for good (user-confirmed).
- jac 0.37 config shape: `[placement] default = "native"`,
  `[placement.pins]`, `[dependencies.pypi]`, `entry-point = "main"`.
- Python deps: `app/jac.toml` **and** root `jac.toml` both list
  `httpx` and `pyte` under `[dependencies.pypi]`. Suites run from the repo
  root use the ROOT project's venv, so a new pypi dep must go in BOTH files.

### Never use `pkill -f <pattern>` on a pattern that appears in your own command
It kills your own shell (exit 144). Use the background task ID instead.

### Never `git commit -a` here
The working tree once had unrelated user deletions; `-a` swept them into a
commit (see §7). Always `git add <explicit paths>`.

### `docs/` is gitignored
`/docs/` is in `.gitignore` (planning docs are local-only). Repo docs that
must ship are force-added: `git add -f docs/TESTING.md`. A plain
`git add docs/...` fails and, inside an `&&` chain, silently skips the commit.

---

## 2. Jac language/compiler lessons (each one cost a CI round-trip)

The CI `check` job (`jac check .` in `app/`) is the type gate. A module that
fails to compile makes **every importer** fail with the misleading
`JacSourceCompileError: No bytecode found for <importer>`. When you see
"No bytecode found", look at the `check` job or the first real
`error[...]` in any log; it is never the module named.

1. **Keywords cannot be identifiers**: `root`, `entry`, `node`, `edge`,
   `walker`, `here`, `visitor`, `self` (as a field), `with`, `flow`, `wait`,
   `has`, `can`, `obj`, `glob`, `test`, `spawn`. `root`/`entry` both broke
   builds this session. Use `base_dir`, `log_entry`, `node_bin`, `tmp_dir`.
2. **One name, one type per function.** Reusing `rows` for `list[dict]` and
   later `list[str]` in the same function is error E1001. Use distinct names.
3. **`str | None` returns must be narrowed** before `.startswith` etc. In
   tests: `str(handle_command(...)).startswith(...)`.
4. **`flow f(x)` requires sendable args (E1308).** An `any`-typed variable,
   or a list that is also stored elsewhere (aliased), is not sendable. Pattern
   that works (mirrors `_attach_mcp_servers`):
   ```jac
   specs: dict[str, list[str]] = {name: [str(c) for c in cmd]};
   for (n, argv) in specs.items() { flow worker(n, argv); }
   ```
5. **`x in y` where `y` is `any`** fails native lowering (E1124). Bind to a
   typed local first: `rows: dict[int, Row] = s.rows; if k in rows {…}`.
6. **Unknown attribute types** (`signal.SIGTERM`) cannot be passed where
   `int` is expected. Use literals (`15`, `9`) or `int(...)`.
7. **Two consecutive docstrings** (a leftover docstring followed by a
   function's own docstring) is a syntax error (E0005). After moving code, check
   for orphaned `"""…"""` blocks.
8. **Tests**: `X.test.jac` is merged into `X.jac` (same stem, same dir); the
   runner IMPORTS `X.jac`, so **every test file needs a same-stem module**,
   even an import-only one (see `app/e2e/print_mode.jac`). Symbols of `X.jac`
   are visible in the test without imports.
9. **Test annex leakage**: importing a module whose `.test.jac` exists can
   pull that annex's tests into YOUR suite's run (e.g. `llm.test.jac` tests
   showed up under `agent_tools`, `chains`, …; `session.test.jac` tests show
   up under `main` and `ui/keybinding_probe`). So one broken test appears in
   many suites. Fix the source suite and the copies disappear.
10. `with entry { … }` runs on import; `with entry:__main__ { … }` runs only
    as a program. Modules tests import must use `:__main__` (done for
    `tui/shell.jac`).
11. Avoid Python builtin `any(...)` in Jac (clashes with the `any` type);
    write a loop.
12. Default placement is native; modules importing Python-only stdlib
    (`unicodedata`, `codecs`, `pyte`, `subprocess` …) are auto-demoted to the
    server codespace with a `note:`. That is fine, not an error.
13. On a cold cache, `jac run` prints many `native seam -- demoting …` lines
    to the terminal before the app starts. Harmless, but it pollutes the PTY
    screen (the PTY e2e boot marker is `● ready` for this reason) and is ugly
    for users (see Phase D item 6).

---

## 3. What exists now (all on `main`)

### CI: `.github/workflows/app-tests.yml`
- Composite action `.github/actions/setup-jac`: downloads jac 0.37.25 release
  binary (sha256 pinned), caches it, runs `jac install` in the repo root AND `app/`,
  exports `JACKAL_ROOT`, `JACKAL_AGENT_DIR`.
- Jobs: `check` (`cd app && jac check .`), and `test` matrix shards
  `agent | tui | ui | e2e | other`, each running `scripts/test.sh -j3
  --quarantine scripts/test-quarantine.txt <subtree>`.
- Logs are uploaded as artifacts `testlogs-<shard>` (hidden dir, so
  `include-hidden-files: true`).
- Concurrency: PR runs cancel, main-branch runs never cancel (one per sha).
- A full run takes ~10–15 min (e2e is the slowest shard).

### Reading results
```bash
scripts/ci-failures.sh            # latest run on this branch
scripts/ci-failures.sh RUN_ID     # specific run
```
It downloads artifacts to `.ci-logs/<run>/` (gitignored), prints each failing
suite's first error lines, and the `jac check` errors. Workflow to wait:
```bash
R=$(gh run list -L 1 --json databaseId -q '.[0].databaseId')
# run in background (run_in_background: true), output to a file:
until [ "$(gh run view $R --json status -q .status)" = completed ]; do sleep 20; done; scripts/ci-failures.sh $R > /home/jac/.cc-res.txt 2>&1
```
Note `gh run view --log` only works after the whole run completes; artifacts
of finished jobs are downloadable earlier with `gh run download $R -n testlogs-e2e`.

### `scripts/test.sh`
Per-suite isolated `jac test` processes; `-jN`, path-substring filters,
`-k keyword`, `--exclude PATH`, `--fail-fast`, `--quarantine FILE`.
Statuses: PASS, FAIL, TIMEOUT, **FLAKY** (crashed with 134/139/"dumped core",
passed on the single automatic retry: counts as pass and is listed), XFAIL
(quarantined failure: non-fatal), XPASS (quarantined but passing: delete it
from the file). Writes a GitHub step summary.

### `scripts/test-quarantine.txt`
Known pre-existing failures, each with a reason: `ui/gates`, `ui/renderer`,
`ui/host`, `ui/virtual_terminal`, `ui/demo_complex_shell` (native core
dumps), `cordis/core` (assertion failures at core.jac:55/64/84/92). Never
quarantine something you broke.

### Offline mock model: `MockTransport` in `app/agent/llm_transport.jac`
Model id `mock` / `mockllm` / `mock/*`. Env:
- `JACKAL_MOCK_SCRIPT=path.json`: a JSON list; each model call consumes one step:
  `{"text": "…"}`, `{"text": "", "tool_calls": [{"name": "edit_file", "args": {…}}]}`,
  `{"error": "HTTP 500: …"}`. Missing file or exhausted means echo `mock: <last user msg>`.
- `JACKAL_MOCK_LOG=path.jsonl`: one line per call:
  `{"call", "messages", "last": {"role","content"}, "tools": [names]}`.
- Text is streamed in two chunks. Subagents and LLM compaction consume steps too.
- The cursor is per process (glob `_mock_cursor`) keyed by script path.
- **Session model is read at import** (`session_state.model` from
  `JACKAL_MODEL`). In-process tests must call `restore_model("mock")`
  (no credential check); subprocesses just set `JACKAL_MODEL=mock`.

### In-process TUI harness (the Pi equivalent): the most important tool
- `app/ui/emulated_terminal.jac`: `EmulatedTerminal(Terminal)` backed by
  **pyte** (real VT emulator). Read-back: `viewport()`, `viewport_text()`,
  `scroll_buffer()`, `cursor() -> (x,y)`, `cell(r,c) -> {char,fg,bg,bold,
  italics,underscore,reverse}`, `find(text) -> (row,col)|None`,
  `line_with(text)`, flags `alternate_screen`, `bracketed_paste`,
  `cursor_visible`, `title`, `eof`. Drivers: `send_input`, `send_key(name)`
  (`KEY_SEQUENCES`: enter, esc, tab, backspace, arrows, home/end, page_up/down,
  delete, shift+tab, ctrl+a/c/d/e/k/l/u/w), `send_paste`, `resize`,
  `close_input`.
- `app/tui/shell.jac` now exposes `create_live_shell(term)`,
  `boot_tui(term) -> LiveShell`, `tui_step(app, poll_timeout_s) -> bool`,
  `shutdown_tui(app)`. `run_tui()` is just boot plus a step loop.
  `LiveShell.term` is typed `Terminal`; the base `Terminal` gained `eof` and
  `poll_input()`.
- `app/tui/harness.jac`: `open_tui(columns, rows, files, script, mode) ->
  TuiHarness` (temp project, chdir, env, mock model, boots the REAL shell).
  `TuiHarness`: `step(n)`, `type_text`, `press(key)`, `paste`, `resize`,
  `screen()`, `wait_for(text)`, `wait_gone(text)`, `wait_idle()` (phase ready
  and no worker), `calls()`, `read(rel)`, `exists(rel)`, `dump()` (framed
  screen + cursor + phase + model calls), `close()` (ALWAYS in `finally`).
- Tests: `app/ui/emulated_terminal.test.jac`, `app/tui/harness.test.jac`.
- UI text to assert on: status `● ready`, prompt `❯ `, plan prompt
  `[plan] ❯ `, turn marks `◆ you`, `◇ jackal`, `▣ tool`, `· system`;
  approval shows `? approve <tool>` and status `◈ approve`; keys y/a/enter
  accept, n/r/esc reject; mode badges ` AUTO `, ` YOLO `, ` PLAN `, ` ASK `;
  esc on an idle prompt quits.

### Subprocess e2e harness: `app/e2e/`
- `harness.jac`: `make_sandbox(files) -> Sandbox` (`project`, `agent_dir`,
  `script(steps)`, `calls()`, `read/write/exists`, `explain(r)`,
  `cleanup()`), `run_jackal(sb, args, stdin_text, env_extra) -> RunResult`
  (`code`, `stdout`, `stderr`, `events()`, `event_types()`, `describe()`),
  `jsonl(kind, text, extra)`, `fixture_path(name)`,
  `write_project_config(sb, cfg)` (writes `.jackal/config.json`),
  `spawn_tui(sb, cols, rows) -> TuiSession` (real `jac run tui/shell.jac`
  under a PTY, output replayed into an `EmulatedTerminal`).
- Suites (each with a same-stem import-only `.jac`): `print_mode`,
  `json_protocol`, `repl`, `integrations` (fake MCP server
  `fixtures/fake_mcp.py`, subagent, task board), `tui` (PTY smoke).
- Use `sb.explain(r)` as the assertion message (includes model calls).

### Docs
`docs/TESTING.md` (force-added): the user guide for all of the above.
`AGENTS.md` "Tests" section points to it.

### Product features added this session (all on main)
- `app/agent/cli.jac` + `app/main.jac`: `jackal -p PROMPT` print mode (stdin
  appended), `--output-format text|json|stream-json`, `--model`,
  `--thinking`, `--mode`, `-c/--continue`, `-r/--resume ID`, `--max-turns`,
  `--json`, `-h`, `-V`. Exit codes 0 / 1 (error) / 2 (usage). `user_argv`
  strips the `jac run main.jac --` prefix.
- Headless approvals now follow the dev mode (`make_approver`): term prompts
  y/N, JSONL waits for `{"type":"approval","approved":bool}` after the
  `approval_request` event, print mode denies confirm-gated tools with a hint.
- `app/agent/agent_tools.jac`: model tools `list_tasks`, `create_task`,
  `update_task`, `delete_task`, `subagent` (nested react loop, fresh context,
  catalog prompt/tools/model, parent cancel, cannot prompt for approval).
- Compaction: `compact_history()` keeps the system prompt and never orphans
  tool results; `/compact` (TUI + REPL).
- `/clear` and `/new` mint a new session id (no transcript overwrite).
- `app/agent/auth_env.jac`: `hydrate_auth_environment()` (all frontends),
  `logout_provider()`, `/logout`.
- TUI: `/help`, `/new`, `/compact`, `/context`, `/mode NAME`, `/logout`.
- MCP: `plugins.mcp_status`/`mcp_notices`, no stdout prints, TUI drains
  notices into the transcript, `mcp_restart(name)`, REPL `/mcp` and
  `/mcp restart NAME`, `wait_mcp_ready()` (bounded by `JACKAL_MCP_WAIT_S`,
  default 10 s) before each turn.
- Project config also loads from `.jackal/config.json` (previously a
  `.jackal` FILE made the sessions/tasks DIR impossible).

---

## 4. CI state at handoff

Last fully read run (before the pyte harness commit `50425d1aa`):
- `check`: **green**. `tui` shard: **green**.
- `agent`/`main`/`ui/keybinding_probe`: 3 tests in `agent/session.test.jac`
  fail (they show in the other suites through annex leakage, §2.9):
  "session_boot parallel sidecar loads fixture…", "unsupported requires fail
  loud at load", "session_boot mirrors extension commands…".
- e2e: subagent scenario prints the nested report instead of the main
  answer; JSONL approval test failed on a double `approval_request` (FIXED
  in 50425d1aa); stdin print test failed on a missing script file (FIXED);
  PTY TUI boot never reached `● ready` because the real TUI crashed on
  `constraints/solver_dual.jac:30` (E1124, see Phase A2).
- other: `constraints/roundtrip` dumps core intermittently (now covered by
  the FLAKY retry), `cordis/core` (quarantined).

2026-10-18 session RESULT (HEAD `afc38e108`, run 39175167065): `check`, `agent`,
`tui`, `e2e` all green — including PTY `e2e/tui` 16/16, `e2e/integrations`
16/16 (A4 done: read-only tools auto-approve in normal mode + subagents; the
nesting test runs in auto-accept), `other/main` 337 passed (A3 done: the warm
flow reads sidecar decls from plugin state instead of taking the list as a
flow argument — E1308/own-unbound; tests now block on the warm future and
print `plugins.detail` on failure), `constraints/roundtrip` 36/36.
Remaining red: `constraints/solver`, `ui/layout`, `ui/layout_compile` (native
core dumps — the A2b upstream segfault), plus quarantined `cordis/core` and
`ui/{gates,host,renderer,virtual_terminal,demo_complex_shell}`.

Run `38068166080` (commit `50425d1aa`, the pyte harness) RESULT (stale):
- `check` green; `tui` shard green **including the new `tui/harness` (all 9
  in-process scenarios) and `ui/emulated_terminal`**. The Pi-style harness works.
- Remaining failures are exactly Phase A items: A2 (solver_dual crash → PTY
  `e2e/tui` never boots), A3 (3 `session.test` sidecar tests, also shown under
  `main` and `ui/keybinding_probe`), A4 (subagent e2e). Everything else is
  quarantined/FLAKY. So skip A1 and start at A2.

---

## 5. The plan

Work strictly in order. One logical change per commit. After each push, wait
for CI and read `scripts/ci-failures.sh` before the next change that depends
on it. Batch independent fixes into one push to save CI time.

### Phase A: make CI trustworthy (green except quarantine)

**A1. Read run 38068166080.** Expect new failures in the brand-new
`tui/harness` and `ui/emulated_terminal` suites. Typical causes and fixes:
- pyte API: `pyte.HistoryScreen(columns, lines, history=N, ratio=0.5)`,
  `pyte.Stream(screen)`, `screen.display` (list[str]), `screen.cursor.x/.y/
  .hidden`, `screen.buffer[row][col]` → Char(`data, fg, bg, bold, italics,
  underscore, strikethrough, reverse, blink`), `screen.history.top` (deque of
  row dicts), `screen.resize(lines, columns)`, `screen.title`, `screen.reset()`.
  Colors: `fg` is `"default"` or names like `"red"`.
- If `wait_for` times out, the failure prints `h.dump()`; read the framed
  screen. If the screen is blank, `_render` probably writes nothing, so check
  `tui/overlay.jac:_render` → `render_frame(app.renderer, app.shell.screen,
  app.term)` and whether it needs `term.columns/rows` set (EmulatedTerminal
  sets them in `init`).
- If key presses do nothing: the normalizer (`ui/input.jac InputNormalizer`)
  holds a lone `\x1b` until a later idle tick flushes it. `press()` steps 2
  ticks; raise to 3 if needed. Enter must be `\r`.
- If typing is lost while `phase == "streaming"`: expected. Use
  `wait_idle()` before typing again.
- `open_tui` mutates process-global session state; every test must `close()`
  in `finally`. If tests interfere, call `clear_history()` and
  `set_current_session_id("")` in `open_tui`.
- If `type_text` assertions fail because of the slash popup, note that typing
  `/` opens an autocomplete popup that owns up/down/tab/enter/esc; a
  fully-typed command plus enter submits.

**A2. Fix the TUI boot crash (real product bug).** STATUS 2026-10-18: the E1124s are FIXED and the PTY TUI boots (`e2e/tui` 16/16, HEAD `afc38e108`), but fixing them exposed an UPSTREAM native-codegen segfault (see A2b). `app/constraints/solver_dual.jac:25-30`:
```jac
def _solver_remove_core(s: any, tag: Tag, strength: StrengthTier, jnl: MutationJournal) -> SolveResult {
    ...
    marker = tag.marker;
    if marker in s.rows {      # E1124: `in` over Any
```
**DO**: `rows: dict[int, Row] = s.rows;` then `if marker in rows {`. Import
`Row` the same way `constraints/solver_journal.jac:123` does (check its
imports for where `Row` comes from). Grep the constraints package for other
`in s.<field>` on `s: any` and fix them the same way:
`grep -n " in s\.\| in self\." app/constraints/*.jac`.
Verify: the e2e `tui` PTY suite reaches `● ready`. DONE 2026-10-18 (`e2e/tui` 16/16 in run 39175167065).

**A2b. UPSTREAM jaclang segfault (open, human-owned).** Fixing the last E1124
at `solver_simplex.jac:300` (`if art in s.rows`, s: any) lets the module lower
natively, and then `constraints/solver`, `ui/layout`, `ui/layout_compile` dump
core under `jac test` (no output, both attempts). Six condition forms all crash
identically: typed local, typed helper fns, `.get(...) is not None`,
`in sorted(s.rows.keys())`, typed bool, and a `sorted()+keys()+==` key loop
(current HEAD — uses only constructs that lower cleanly everywhere else).
So the fault is NOT the condition: it is native execution of
`_solver_add_with_artificial_variable` (or the newly-native module), i.e. a
jaclang native-codegen bug under jac 0.37.25 (latest per jacup index).
Evidence: with the E1124 left in place the module demotes to server and all
three suites pass; `constraints/roundtrip`'s crash in run 39161578782 was the
known intermittent flake (passes now, 36/36). Owner: jaseci-labs/jac. Minimal
fix for the human: build a small repro from `_solver_add_with_artificial_variable`
(Row construction, `dict(row.cells)` copies, `_solver_optimize_toward` with the
`extra: Row | None` param) and file it upstream. Do NOT quarantine
solver/layout/layout_compile (rule: never quarantine something you broke).
Workaround if the TUI must ship before upstream fixes it: none found — every
lowering-safe form crashes; reverting line 300 to `if art in s.rows` restores
solver green but re-breaks PTY TUI boot with E1124.

**A3. Fix `agent/session.test.jac` sidecar tests.** They pass `os.getcwd()`
as the base dir for extension fixtures (lines ~46, 78, 144), but suites run
from the REPO ROOT, so `plugin_host/fixtures/...` is not found. **DO**: apply
the same fix as `agent/plugin_hooks_events.test.jac` (search it for
`app_root`):
```jac
app_root: str = os.getcwd();
if not os.path.isdir(os.path.join(app_root, "plugin_host")) {
    app_root = os.path.join(app_root, "app");
}
```
and use `app_root` where those tests pass `os.getcwd()` for fixture
resolution. Also grep all tests for the pattern:
`grep -rn 'getcwd(), "plugin_host"\|getcwd()' app --include=*.test.jac`
(zsh: run `grep -rn ... app | grep test.jac`; `--include` globbing errors
under zsh). Node must exist in CI; the workflow already sets up node 20.

**A4. Subagent e2e** (`app/e2e/integrations.test.jac`, "subagent runs a
nested loop"). The observed stdout was the nested report ("the word is
kumquat"), meaning the main loop consumed script step 2. The explain() output
now includes the model calls; read them. Likely causes, in order:
1. The nested loop never ran its read_file call (the `child` registry lacked
   `read_file`, or the nested approve denied it). `read_file` should be
   "auto" in normal mode; check `modes.requires_approval("normal",
   "read_file", "")`: normal mode returns "confirm" for EVERYTHING not
   blocked. **That is the bug**: in normal mode the subagent's
   `_subagent_approve` refuses read_file, the nested loop ends after one call
   with whatever text, then the main loop gets step 2. **DECIDE (default)**:
   read-only tools (`read_file`, `list_dir`, `glob`, `grep`, `web_search`,
   `web_fetch`, `list_tasks`, `jac_check`) are auto-approved inside
   subagents in every mode except where `is_tool_blocked`. Implement in
   `agent_tools._subagent_approve` with a `READ_ONLY_TOOLS` set. Also
   consider whether the MAIN loop should auto-approve read-only tools in
   normal mode. Check `tui/runtime.jac approve()`: it uses
   `requires_approval`, so currently normal mode prompts even for
   `read_file`. If that is the case, it is a UX bug; **DECIDE**: make
   `modes.requires_approval` return "auto" for the read-only set in normal mode
   (update `agent/modes.test.jac` accordingly) and say so in the commit.
2. Then re-run; the test expects 4 calls in the order main → nested → nested → main.

**A5. Iterate** until every shard is green or XFAIL/FLAKY only. Delete
XPASS lines from the quarantine as they appear. When green, tell the user
in one line.

### Phase B: grow the harness coverage (use it to check features)

Add scenarios to `app/tui/harness.test.jac` (in-process, fast, preferred)
and `app/e2e/*` (process-level). Each test: arrange a script, drive, assert
on screen plus `calls()` plus files. Priority list:
1. Abort: start a long scripted turn, `press("esc")` while streaming (status
   hint says "streaming · esc abort"), assert the phase returns to ready and
   the transcript shows the cancel.
2. History: submit two prompts, `press("up")` recalls the previous one in the editor.
3. Multiline/paste: `h.paste("line1\nline2")` shows both lines in the editor.
4. Pickers: `/resume` opens the session picker after a saved turn (it needs
   a previous turn in the same project: run one turn, `/new`, `/resume`, enter).
   `/tasks` after a `create_task` tool call. `/mcp` with
   `.jackal/config.json` pointing at `app/e2e/fixtures/fake_mcp.py`
   (in-process: `files={".jackal/config.json": json.dumps(cfg)}`).
5. Model picker: `/model ` then down/enter changes the status line model.
6. Rendering invariants (Pi has these): after any scenario, every viewport line
   satisfies `len(line) <= columns`; no stale characters after shrinking text
   (type 20 chars, backspace 15, the line equals the 5-char prefix); wide/emoji
   text (`"界界界"`) does not misalign the status line.
7. Markdown: a scripted answer with `**bold**` renders bold cells
   (`h.term.cell(r, c)["bold"]`) and does not show the asterisks.
8. Error surfacing: script `{"error": "HTTP 500: boom"}` and the transcript shows it.
9. Plan mode: `mode="plan"`, a write tool call is blocked; the transcript shows
   the reason and no modal appears.

### Phase C: daily-driver feature gaps (from the audit; verify each with Phase B tests)

Ranked. Each item names the files, the approach, and how to test it.

1. **Streaming performance.** `tui/runtime.jac` (`_drain` around lines 137–212):
   every chunk re-renders the whole assistant message (quadratic), and the
   event queue is unbounded. **DO**: accumulate chunks and rewrite the
   streaming turn at most once per tick (the loop already drains per 40 ms
   tick; make sure `_rewrite_turn` is called once per drain, not per chunk).
   Test: a script with a 20 KB text answer; assert it completes within N
   steps and the final screen shows the tail.
2. **Read-only tools auto-approved in normal mode** (see A4.1). Small; high UX value.
3. **Tool result display.** Tool results are cut to 200 chars on one line
   (`runtime.jac:165`). **DO**: show the first ~6 lines plus "… (N more lines)";
   keep the full text in history. Optional: ctrl+o toggles expansion of the
   last tool result.
4. **TUI MCP overlay** (`tui/mcp.jac`) should read `plugins.mcp_status` (state,
   tools, error) and use `mcp_server_specs` from `agent.session` instead of
   its hand copy `_local_mcp_server_specs`. Add `/mcp restart NAME` in
   `tui/commands.jac` → `mcp_restart`. Keep the replica in
   `tui/overlays.test.jac` in sync or delete the replica test and cover it
   with the harness.
5. **Extension shortcuts bound to keys** (`agent/plugin_bridge_traffic.jac:89`
   says "not yet bound"). `tui/input.jac` around line 280 already routes keys
   to `run_extension_shortcut` for "global binding semantics"; verify with
   `fake_host.register_fake_shortcut` in a harness test and fix the gap.
6. **Cold-start compiler noise.** First `jac run` prints `native seam --
   demoting …` lines. **DECIDE**: launch with stderr captured during import;
   simplest is a thin launcher (item 7) that runs `jac build` once and hides
   that output. Do not spend more than one commit on it.
7. **Launcher/install.** `jackal.sh` was deleted by the user and AGENTS says
   "no launcher script". **DECIDE (default)**: do NOT add a shell launcher;
   document `jac run app/main.jac -- …` and `jac run app/tui/shell.jac` in
   README/AGENTS (done). Ask the user before adding any `bin/` entry point.
8. **OAuth login** (`agent/auth_network.jac:20,40` stubs return
   `network_not_supported`; `tui/picker_actions.jac:132` reports it). This is
   larger: implement the device/PKCE flow for one provider first (OpenRouter
   supports PKCE OAuth: `https://openrouter.ai/auth?callback_url=…&code_challenge=…`
   then POST `https://openrouter.ai/api/v1/auth/keys` with the code, which returns
   an API key). Store it as `{"type":"api_key","key":…}`. Needs a localhost
   callback server (Python `http.server` in a flow) and opening the browser
   (`webbrowser.open`). Test: unit-test the PKCE helpers; skip network in CI.
   **Ask the user** before starting OAuth; it is optional for completeness.
9. `/stats` in the line REPL is gone from help; `show_stats` is a glob in
   `session_state` that cannot be toggled through the facade. Leave it.

### Phase D: roadmap items (only after A–C, confirm with the user)
- N6 "zero server pins" is compiler work (`ROADMAP.md` §N6); not product work.
- Cordis integration (N4); `cordis/core` tests are quarantined and failing;
  fix them before any N4 work.
- Packaging/session migration docs (N3).

---

## 6. How to write a new test (copy-paste templates)

In-process TUI (preferred):
```jac
test "name" {
    h = open_tui(files={"a.txt": "x\n"}, script=[{"text": "done"}], mode="normal");
    try {
        h.type_text("do it");
        h.press("enter");
        h.wait_for("done");
        h.wait_idle();
        assert h.term.find("◇ jackal") is not None, h.dump();
    } finally {
        h.close();
    }
}
```
Process e2e:
```jac
test "name" {
    sb = make_sandbox({"a.txt": "x\n"});
    try {
        sb.script([{"text": "ok"}]);
        r = run_jackal(sb, ["-p", "q"]);
        assert r.code == 0, sb.explain(r);
    } finally {
        sb.cleanup();
    }
}
```
A new e2e suite `app/e2e/foo.test.jac` needs `app/e2e/foo.jac` containing
just `import from e2e.harness { … }`.

Unit test for module `app/x/y.jac`: create `app/x/y.test.jac`; module
symbols are in scope; annotate locals whose type the checker cannot infer.

---

## 7. Open items to raise with the user (don't decide alone)

1. ~~vendor/ deletion~~ — resolved: the user confirmed `vendor/` is not needed; the deletion in `c5d67da15` stays. AGENTS.md updated.
2. Normal-mode auto-approval of read-only tools (A4) is a behavior change;
   mention it in the summary.
3. OAuth scope (C8).

---

## 8. Definition of done

- CI: every shard green, with only quarantined XFAIL and FLAKY entries, each
  quarantine line carrying a reason.
- Harness tests (Phase B list) exist and pass; any user-visible TUI behavior
  can be checked by writing a 10-line `open_tui` test.
- Phase C items 1–5 done and covered by tests.
- `docs/TESTING.md` and this file updated to reflect reality; delete
  `HANDOFF.md` once everything here is done (or replace it with a short status).
