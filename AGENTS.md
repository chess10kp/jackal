# Jackal — Agent onboarding (read this first)

Jac-native terminal coding agent.

> **Native-first (current truth):** the all-Jac harness under `app/` **is**
> Jackal — a native agent loop, a custom differential TUI (`app/tui/` LiveShell
> + `app/ui/` OSP framework), and a Pi-compatible Node sidecar for JavaScript
> extensions (`app/plugin_host/`). It is compiled with **neojac 0.5.3** in the
> neojac 0.5 project format: declarations in `*.jac`, bodies in
> `impl/*.impl.jac`, cross-module imports in `app/archwire.jac`. The old
> TypeScript runtime is gone; `tui/js2jac/` is an active conversion workstream.
> See [`docs/DEV-VM.md`](docs/DEV-VM.md) for the current build/test status.

---

## You are in the development VM

- This checkout is `/data/home/repos/jackal` (`~/repos/jackal`) on the
  **jackal-extra-1** Instabox machine. Commands run here directly — there is
  no `instabox ssh`/`exec` wrapper in the loop.
- Machine: 4 vCPU / 8 GiB (facts in `~/MACHINE.md`). Cap parallel builds and
  tests; run `app/e2e/` serially.
- Persistent scratch space: `/data/workspace`.
- Installed: Node 22, OpenSSL headers, neojac 0.5.3 at `~/.local/bin/neojac`.
  **No** `jac`, `./jac`, `vendor/jac`, or Zig — the vendored-compiler workflow
  is historical (`docs/VENDOR-JAC.md`).
- GitHub credentials may not be configured on a fresh box; check before
  push/pull.

---

## Rules for agents working in this repo

1. **Commit** after each feature or bugfix (unless the user says otherwise).
   Add explicit paths; this tree has carried unrelated working-tree changes.
2. **Use neojac 0.5.3.** `neojac build`, `neojac test`, `neojac check`,
   `neojac fmt` — from `app/` (the neojac project root). Do not run
   `scripts/setup-vendor-jac.sh`, `scripts/setup-macos.sh`, `scripts/test.sh`,
   or `jac build`: they target the retired `jac` toolchain and cannot run here.
   Do **not** build with `neojac-0.3.2`; it rewrites sources into a different
   layout and the next build fails with E1141/E2097.
3. **Respect the 0.5 project layout.** Put function bodies in
   `impl/X.impl.jac`, not back into `X.jac`; put cross-module imports/wires in
   `app/archwire.jac`. Run `neojac fmt` when in doubt — it owns the split.
4. **Placement discipline.** `app/jac.toml` sets `[placement] default =
   "native"` with explicit `[placement.pins]`. Change a pin only in a
   deliberate commit with a stated reason, and keep `neojac build` green.
5. **Forward product work** lands in `app/`, its tests, and docs.
   `tui/js2jac/` is a separate workstream (`tui/js2jac/SYNC.md`).
6. **Compiler/toolchain gaps:** report upstream to jaseci-labs/jac (neojac
   releases). There is no vendored compiler in this checkout, so work around
   in `app/` (usually by annotating types) and note the blocker — do not patch
   a compiler here.
7. **Delivery:** for user-visible changes build a fresh binary. Target this
   VM's platform (`linux-x86_64`) unless told otherwise, leave it in the
   normal output path — `app/.jac/bin/jackal-tui` (TUI) and
   `app/.jac/bin/jackal` (CLI/REPL) — and report that exact path. Run the
   affected `neojac test` modules; if the full suite cannot run, state the
   specific blocker and what was verified.

---

## Build and run

```bash
./run.sh                                  # TUI: neojac build if missing, then exec
JACKAL_ENTRY=main ./run.sh --json         # CLI/REPL frontend
./bin/jackal-tui                          # pre-built TUI (no neojac)
./bin/jackal -p "hello"                   # pre-built CLI/REPL

cd app
neojac build tui/shell.jac -o .jac/bin/jackal-tui --release
neojac build main.jac      -o .jac/bin/jackal     --release
neojac test agent/auth.jac                # one module
neojac test agent ui tui                  # several trees (run in parallel by the runner)
```

- Builds are content-hash cached: an unchanged tree rebuilds in under 0.1 s and
  leaves the existing binary in place. Touch a source file when you need real
  compiler output to read. A release rebuild after a change is ~11 s.
- Memory-capped test wrappers: `scripts/neojac-test-each.sh OUT MOD...` and
  `scripts/neojac-test-k.sh OUT MOD NAME...` (`systemd-run` with a 4 GiB cap).
  Run `app/e2e/*` **serially** — those suites shell out to `neojac build`, and
  concurrent memory pressure makes clang die
  (`clang integrated assembler command failed with exit code 135`).
- `run.sh`/`bin/*` export `JACKAL_ROOT=<repo>` and
  `JACKAL_AGENT_DIR=<repo>/pi` by default. `pi/` is gitignored/local-only and
  may be absent in a fresh checkout; auth state is then created under
  `<repo>/pi`, and skill discovery falls back to `JACKAL_ROOT`.

Native gotchas: `int` is 64-bit (clamp float sentinels before `int()`);
containers are invariant (annotate `list[dict[str, any]]` literals);
`assert c, msg` needs a `str` msg; imports only at module level;
`sys.executable` is the program itself (never spawn it for Python fixtures —
it fork-bombs the test runner); `bytes.decode(enc, errors)` is positional.

---

## Architecture (one picture)

```
User terminal
    │
    ▼
app/tui/  LiveShell + host loop
    shell.jac facade → impl/shell.impl.jac
    runtime.jac: events → transcript/render loop, streaming, approvals
    input/normalizer, commands, overlays, pickers, windows, context, preview
    │
    ▼
app/agent/  session host
    session_config (session state, MCP, config), session_turn (run_turn,
    compaction), llm_loop (ReAct loop), llm_transport (providers + mock)
    tools/tool_spec/registry, approvals/modes
    auth + openai_accounts/login/identity/responses (ChatGPT account sign-in)
    sessions/tasks/checkpoints/skills/subagents/chains, plugin bridge + hooks
    │
    ▼
app/ui/  OSP differential-TUI framework (terminal + vt_screen, renderer,
         screen/transcript/editor, layout engine via constraints/, markup,
         markdown, focus, gates, keybinding probe, widgets)
```

- **Placement:** `[placement.pins]` in `app/jac.toml` is the single source of
  truth. The UI/agent graph still has server-pinned modules, annotated with
  their unblock condition; `constraints/*` and `core.edit` are native pins.
  N6 (zero server pins) is compiler work, not product work.
- **Plugin host invariant (D21):** JavaScript never blocks the first frame.
  `session_boot` → `wait_extensions_ready` → `run_turn` with `bridge=`.
  Extension commands run off the TUI thread; extension UI requests queue behind
  the approval overlay.
- **Bodies live in `impl/`.** `app/archwire.jac` declares the import wires;
  `app/*/impl/*.impl.jac` hold the implementations.

## Source map (`app/`)

| Path | Role |
|------|------|
| `app/main.jac` | CLI/REPL frontend: `-p`, `--json` JSONL, sessions, approvals |
| `app/tui/` | LiveShell facade (`shell.jac`), host loop (`runtime.jac`), input/normalizer, commands, overlays, pickers, windows, context, preview; bodies in `tui/impl/` |
| `app/agent/` | Session host: `session_config`, `session_turn`, `llm_loop`, `llm_transport`; tools/tool_spec/registry; approvals/modes; auth (`auth*`, `openai_*` account login); MCP client; sessions/tasks/checkpoints/skills/subagents/chains/compaction; plugin bridge (`plugin_bridge_*`) + hooks; bodies in `agent/impl/` |
| `app/ui/` | OSP framework: model/mutation/bindings/events, terminal + `vt_screen` (pyte replacement), renderer/screen/transcript/editor, layout (+measure/quantize/compile), markup/markdown_proj, focus, gates, keybinding_probe, widgets |
| `app/constraints/` | Constraint layout solver — native pins (`algebra`, `solver`, `layout_relations`), plus the `roundtrip` oracle suite |
| `app/core/edit.jac` | Edit/diff kernel — native pin |
| `app/cordis/core.jac` | Cordis-style composition core (revertible effects + reactive coeffects) |
| `app/plugin_host/` | Pi-compatible Node sidecar: `host.mjs`, `pi_shim.mjs`, fixtures |
| `app/e2e/` | Process-level suites: print mode, JSONL protocol, REPL, PTY TUI, integrations |
| `app/archwire.jac` | neojac 0.5 cross-module imports/wires |

Tests live next to code as `<module>.test.jac` (80 files). Module bodies live
in the adjacent `impl/` directory.

---

## Environment variables

| Variable | Used by | Purpose |
|----------|---------|---------|
| `JACKAL_MODEL` | `agent/session_state.jac` | Default model override (`mock` for offline) |
| `JACKAL_CONTEXT_MAX` | `session_turn`, `tui/commands` | Context window cap |
| `JACKAL_AGENT_DIR` | auth, skills, chains, openai accounts | Bundle dir: `auth.json`, `openai-accounts.json`, skills, catalogs. Run scripts default it to `<repo>/pi` |
| `JACKAL_ROOT` | `skills.jac`, `chains.jac` | Repo-root fallback for catalogs |
| `JACKAL_NODE_BIN` | `plugin_bridge_support` | Node binary for the plugin sidecar |
| `JACKAL_LOG` | `agent/logging.jac` | Structured JSONL debug log. `1` → `<cwd>/.jackal/logs/<date>-<pid>.jsonl`; any other value is a sink path. Unset/`0` = off |
| `JACKAL_LOG_LEVEL` | `agent/logging.jac` | `debug`/`info`/`warn`/`error` threshold (default `info`) |
| `JACKAL_SANDBOX_ROOT` | `agent/tools.jac` | When set, file tools reject paths outside this root (lexical `..` containment; off by default) |
| `JACKAL_ALLOW_PRIVATE_HOSTS` | `agent/web_tools.jac` | Offline-test escape hatch: lets `web_fetch` reach loopback/private hosts that the SSRF guard blocks. Never set in a normal session |
| `JACKAL_MCP_WAIT_S` | `session_config` | Seconds to wait for MCP servers before a turn (default 10) |
| `JACKAL_MCP_NO_IMPORT` | `session_config` | Opt out of importing legacy MCP configs |
| `JACKAL_CATALOG_TTL_MS` | `model_catalog` | Model catalog cache TTL |
| `JACKAL_MOCK_SCRIPT` / `JACKAL_MOCK_LOG` | `llm_transport` | Offline mock provider script / call log (see `docs/TESTING.md`) |
| `JACKAL_TUI_BIN` / `JACKAL_BIN` | `e2e/harness` | Override the binary under test in process-level suites |
| `JACKAL_SKIP_NET_TESTS` | `web_tools.test.jac` | Skip network-dependent assertions |

Provider keys come from env (e.g. `OPENROUTER_API_KEY`) or `auth.json`; ChatGPT
account sign-in stores tokens in `openai-accounts.json` (see
[`OPENAI-ACCOUNT-LOGIN.md`](OPENAI-ACCOUNT-LOGIN.md)). Never commit either file.

---

## Tests

- **Local (authority):** `cd app && neojac test <module.jac>`, or
  `neojac test agent ui tui`. Use `-k <text>` for a single test. On this box,
  cap processes with the wrappers above and run `app/e2e/` serially.
- **Status (2026-11-27):** 79 of 80 test modules green; the only red module is
  the quarantined `tui/harness` (known mode-badge `YOLO`/`AUTO` assertions,
  see `scripts/test-quarantine.txt`).
- **CI is stale after the 0.5 migration.** `.github/workflows/app-tests.yml`
  still installs `jac` 0.38.2 and runs `jac check .` plus `scripts/test.sh`;
  that compiler cannot parse `app/archwire.jac` (E0005/E0013), so the run is
  red. The `seal-pins` job (`scripts/seal-pin-guard.py`) still passes and is
  useful. Do not treat a green CI run as coverage for 0.5 changes; migrate the
  workflow before relying on it.
- **Mock provider:** `JACKAL_MODEL=mock` with `JACKAL_MOCK_SCRIPT` /
  `JACKAL_MOCK_LOG`; deterministic, keyless, offline. Details in
  [`docs/TESTING.md`](docs/TESTING.md) (the runner sections predate neojac).
- **Seal static check:** `python3 scripts/seal-pin-guard.py` after moving code
  across the native/server boundary.

---

## Human handoff

| Symptom / need | Owner | Notes |
|----------------|-------|-------|
| Native lowering gaps in `app/` | jaseci-labs/jac (neojac) | Work around in `app/` (annotate types), report upstream; no vendored checkout here |
| JS plugin-host / Pi compatibility gaps | `app/plugin_host/` | Sidecar must not block the first frame (D21) |
| `js2jac` converter gaps | jac_llm_data fork | Sync contract in `tui/js2jac/SYNC.md` |
| CI migration to neojac 0.5 | repo human | `.github/workflows/app-tests.yml` still pins `jac` 0.38.2 and fails on `archwire.jac` |
| ChatGPT account consent / live refresh / revocation | user | Automated fixtures do not prove live authorization (`OPENAI-ACCOUNT-LOGIN.md`) |

---

## Docs index (deeper dives)

| Doc | Contents |
|-----|----------|
| [`README.md`](README.md) | Product summary and VM pointer |
| [`docs/DEV-VM.md`](docs/DEV-VM.md) | **Current** VM toolchain, binaries, build/test status and box-specific gotchas |
| [`docs/TESTING.md`](docs/TESTING.md) | Mock provider, E2E/TUI harness, quarantine, seal reading (jac-era runner) |
| [`docs/NATIVE-LOWERING-GAPS-UI-STATE.md`](docs/NATIVE-LOWERING-GAPS-UI-STATE.md) | Native lowering frontier and compiler gaps |
| [`docs/PLUGIN-UI-ROUNDTRIP-PLAN.md`](docs/PLUGIN-UI-ROUNDTRIP-PLAN.md) | Extension `ctx.ui` round-trip design |
| [`docs/LAYOUT-ENGINE-PLAN.md`](docs/LAYOUT-ENGINE-PLAN.md) | Constraint layout engine plan |
| [`docs/VENDOR-JAC.md`](docs/VENDOR-JAC.md) | Historical vendored-compiler workflow (`vendor/` is not present) |
| [`ROADMAP.md`](ROADMAP.md) | Positioning and binding decisions (status dated 2026-08-30) |
| [`CURRENT.md`](CURRENT.md), [`HANDOFF.md`](HANDOFF.md) | Historical session notes (2026-10); verify before trusting |
| [`tui/js2jac/SYNC.md`](tui/js2jac/SYNC.md) | js2jac conversion workstream contract |
| [`OPENAI-ACCOUNT-LOGIN.md`](OPENAI-ACCOUNT-LOGIN.md) | ChatGPT account sign-in: flow, storage, verification |

---

## Practical gotchas (lessons from working in this repo)

### neojac 0.5 layout

- `neojac fmt` moves bodies into `impl/*.impl.jac` and imports into
  `app/archwire.jac`. Edit those files, not duplicate declarations in `X.jac`.
- Building with `neojac-0.3.2` rewrites project sources and generates
  conflicting `implementation`/`archwire` files; the next build fails with
  E1141/E2097. Stick to 0.5.3.
- Build caching is content-hash based: if you need compiler diagnostics, touch
  the source first or the build exits instantly with the old binary.

### Native lowering

- Unannotated kwargs and intermediate values block native lowering; annotate
  types until suites/builds lower.
- Placement pins are explicit and deliberate; don't add or remove one casually.
- In Jac tests, `root` is a built-in reference name; use `tmp_dir` or similar.
- `node` is a Jac keyword → use `node_bin` in plugin-host code.
- Never build with `pkill -f <pattern>` matching your own command line; it
  kills the shell (exit 144).

### Plugin host (D21)

- Invariant: **JS does not block the first frame** — not "JS never starts at boot."
- Product seam: `session_boot` → `wait_extensions_ready` → `run_turn` with `bridge=`.
- Extension commands run OFF the TUI thread; extension UI requests queue behind
  the approval overlay.

### Working in `app/`

- The TUI paint/layout logic lives in `app/ui/demo_live_shell*` (upstream of
  `app/tui/shell.jac`); change paint behavior there, not in the shell driver.
- `docs/` is gitignored; force-add new docs with `git add -f docs/<file>`.
- `pi/`, `openai-accounts.json`, and `auth.json` are private local state; never
  commit or print them.
- Prefer `git add <explicit paths>` over `git commit -a`.
