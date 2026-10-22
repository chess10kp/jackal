# Jackal — Agent onboarding (read this first)

Jac-native terminal coding agent.

> **Native-first (current truth):** the all-Jac harness under `app/` **is** Jackal — a native Jac agent loop, a custom differential TUI (`app/tui/shell.jac` LiveShell + `app/ui/` OSP framework), compiled with `default_codespace = "native"` (`app/jac.toml`). There is no N3 "cutover" pending; the port happened. What remains under `src/`, `templates/`, and `tui/` is **LEGACY-PENDING-REMOVAL** (see below). See [`ROADMAP.md`](ROADMAP.md) and [`docs/NA-HARNESS-EXPLORATION.md`](docs/NA-HARNESS-EXPLORATION.md).

---

## Rules for agents working in this repo

1. **Commit** after each feature or bugfix (unless the user says otherwise).
2. **Do not modify** `jac-client`. There is no vendored compiler: jac is the jacup-managed release (0.37.25). Compiler bugs go upstream to jaseci-labs/jac (see Human handoff).
3. **Native lowering discipline:** write Jac that lowers natively — annotate types (including kwargs and intermediates) so modules lower without implicit server fallback; keep `jac build` green on `app/`; change `[placement.pins]` in `app/jac.toml` only via deliberate commits with a stated reason.
4. **Do not extend legacy code.** `src/`, `templates/`, `tui/*.tsx`, `lib/jac/`, and the TS test suites are frozen pending deletion. No new features, no fixes unless a deletion commit depends on it.
5. **Framework/plugin gaps** → stop, document symptom + owning repo + minimal recommended fix for the **human** (see [Human handoff](#human-handoff)).
6. **Forward product work:** `app/`, its tests, and docs.

---

## Quick start (dev)

```bash
# Native harness (the product)
cd app && jac run main.jac     # term REPL frontend (--json for JSONL protocol)
jac run tui/shell.jac                # native TUI (TTY required)

# Build / check
cd app && jac build            # native compile check over app/
jac test app/<file>.test.jac   # per-file jac tests
```

**Running:** no launcher script — from `app/`: `jac run tui/shell.jac` boots the native TUI (needs a TTY); headless: `jac run main.jac` (line REPL) or `jac run main.jac -- --json` (JSONL protocol). Set `JACKAL_AGENT_DIR=<repo>/pi` and `JACKAL_ROOT=<repo>` so auth/catalogs resolve.

**Requirements:** `jac` 0.37.25 via jacup (`jacup install 0.37.25`; CI pins the same release binary); a TTY for the TUI; provider API keys via env or auth.json (see below).

---

## Architecture (one picture)

```
User terminal
    │
    ▼
app/tui/shell.jac  LiveShell (native TUI, ~2.4k LOC)
    │   runs run_tui(): raw input → normalizer → event handling → render loop
    │
    ▼
app/agent/session.jac  THE agent loop (server placement)
    ├─ run_turn() on a worker thread; events flow to the UI queue
    ├─ tools (read/write/edit/bash/web/...), approvals (agent/approvals.jac)
    ├─ fx-style provider routing + LLM transport (agent/llm.jac)
    ├─ MCP subprocess clients (agent/mcp.jac → `jac mcp`)
    ├─ sessions/tasks/checkpoints/skills/subagents/chains/compaction
    └─ plugin bridge (agent/plugin_bridge.jac) ⇄ Node sidecar (app/plugin_host/)
    │
    ▼
app/ui/  OSP differential-TUI framework (terminal, renderer, editor,
         transcript, layout engine via constraints/, markdown, focus, overlays)
```

- **Placement:** UI and agent modules are server-pinned by explicit pins in `app/jac.toml`; pure compute targets native (`core.edit` is natively pinned as the dogfooding example). Test suites are being lowered natively suite-by-suite (recent commits annotate types until each suite passes under `default_codespace = "native"`).
- **Plugin host invariant (D21):** JavaScript never blocks the first frame. See [`docs/PLUGIN-HOST-PLAN.md`](docs/PLUGIN-HOST-PLAN.md).

## Source map (`app/`)

| Path | Role |
|------|------|
| `app/main.jac` | Entry: term line REPL frontend; `--json` JSONL protocol for UI clients |
| `app/tui/shell.jac` | LiveShell product TUI: command routing, pickers, approval modal, extension modals |
| `app/tui/overlays.jac` | Overlay components for the TUI |
| `app/agent/` | Session loop, tools, tool_spec/registry, LLM/provider routing, MCP client, sessions, tasks, checkpoints, skills, subagents, chains, compaction, context_input, modes/approvals, auth store + login flow state machine, plugin bridge/hooks, extensions |
| `app/ui/` | OSP UI framework: model/mutation/bindings/events, terminal + virtual_terminal, renderer/screen/transcript/editor, layout (+ measure/quantize/compile), markup/markdown_proj, focus, gates, keybinding_probe, widgets |
| `app/constraints/` | Constraint layout solver (server-pinned; LAYOUT-ENGINE-PLAN §3) |
| `app/core/edit.jac` | Edit/diff kernel — natively pinned |
| `app/cordis/core.jac` | Cordis-style composition core (revertible effects + reactive coeffects) |
| `app/plugin_host/` | Pi-compatible Node sidecar: `host.mjs`, `pi_shim.mjs`, fixtures |

Tests live next to code as `<module>.test.jac` (~55 files across `app/`); run per-file with `jac test`.

---

## LEGACY-PENDING-REMOVAL

These paths are frozen. A deletion commit is upcoming — do not extend them:

| Path | Was |
|------|-----|
| `src/` | TypeScript headless runtime (`dist/index.js`) |
| `tui/*.tsx` + `tui/pi_jac/` | Temporary protocol client against the old seam |
| `lib/jac/` | Python toolchain mirror of the TS runtime (bridge superseded by native port) |
| `tests/` (vitest), npm scripts | Legacy adapter/session/TUI tests |

**Not legacy:** `tui/js2jac/` — active TS→Jac conversion workstream with its own sync contract; see `tui/js2jac/SYNC.md`.

`pi/` remains the config/data bundle (SYSTEM.md, skills, prompts, agents, chains, mcp.json reference). The native harness reads skills/auth/chains catalogs from `JACKAL_AGENT_DIR`, then `JACKAL_ROOT`, then cwd.

---

## Environment variables (native harness, verified in `app/`)

| Variable | Used by | Purpose |
|----------|---------|---------|
| `JACKAL_MODEL` | `agent/session.jac` | Default model override |
| `JACKAL_CONTEXT_MAX` | `agent/session.jac` | Context window cap |
| `JACKAL_AGENT_DIR` | `agent/auth.jac`, `skills.jac`, `chains.jac` | Bundle dir: auth.json, skills, catalogs |
| `JACKAL_ROOT` | `skills.jac`, `chains.jac` | Repo-root fallback for catalogs |
| `JACKAL_NODE_BIN` | `agent/plugin_bridge.jac` | Node binary for the plugin sidecar |

Legacy vars (`JACKAL_HEAP_MB`, `JACKAL_TUI_OUT`, `JACKAL_SKIP_TUI_COMPILE`) belong to the old launcher path and die with the launcher cleanup. Provider keys come from env (e.g. `OPENROUTER_API_KEY`) or `auth.json` (byte-compatible with the legacy pi-ai shape; see `app/agent/auth.jac`).

---

## Tests

See [`docs/TESTING.md`](docs/TESTING.md). Tests run on GitHub Actions — the dev box is compute-constrained, so push and read CI (`gh run download <id>` for `.testlogs/`) instead of running suites locally.

| Suite | Location | Run |
|-------|----------|-----|
| Unit (jac) | `app/**/*.test.jac` | `scripts/test.sh [-j3] [path-substring]` |
| E2E (mock provider, real processes, PTY TUI) | `app/e2e/` | `scripts/test.sh app/e2e/` |
| js2jac converter | `tui/js2jac/` bridge loop | see `tui/js2jac/SYNC.md` |

Offline model for any manual or scripted run: `JACKAL_MODEL=mock` with `JACKAL_MOCK_SCRIPT` / `JACKAL_MOCK_LOG` (see TESTING.md). Known failures live in `scripts/test-quarantine.txt` (with reasons).

Note: a repo-root `jac build` sweeps everything, including legacy `templates/*.cl.jac` (which fail by design — the `.cl.jac` marker was retired) and skill asset samples. Judge build health on the `app/` tree: `cd app && jac build`.

---

## Human handoff

Only entries still true after the native-first pivot:

| Symptom / need | Owner | Notes |
|----------------|-------|-------|
| Native lowering failures in `app/` | jaclang (jaseci-labs/jac) | Work around in `app/` (annotate types), report upstream |
| `js2jac` converter gaps | jac_llm_data fork | Sync contract in `tui/js2jac/SYNC.md` |

Pruned as stale (legacy-runtime-bound, moot after deletion): `@jac/pi` hook naming, facade copy workarounds, formal `--adapter` flag.

---

## Docs index (deeper dives)

| Doc | Contents |
|-----|----------|
| [`ROADMAP.md`](ROADMAP.md) | Product direction, phases, current frontier |
| `docs/NA-HARNESS-EXPLORATION.md` | Codespace and UI decision record |
| `docs/PLUGIN-HOST-PLAN.md` | Parallel Node sidecar; JS must not block first frame (D11/D13/D21); §14 lessons from P0–P5 |
| `docs/VENDOR-JAC.md` | Vendored Jac compiler subtree — build, edit, sync, push-back rules |
| `docs/CORDIS-DESIGN.md` | Dynamic composition design |
| `docs/MCP.md` | MCP client: config schema, approvals, /mcp commands, failure behavior |
| `docs/decisions.org` | Architecture decision log |
| `tui/js2jac/SYNC.md` | js2jac conversion workstream contract |

---

## Practical gotchas (lessons from working in this repo)

### Native lowering

- Unannotated kwargs and intermediate values block native lowering; recent history is a steady stream of "annotate X so suite Y lowers natively" commits.
- Placement pins are explicit and deliberate: the whole layout path stays server-pinned; `core.edit` is the showcase native pin. Don't add pins casually.
- In Jac tests, `root` is a built-in reference name; use `tmp_dir` or similar instead.
- `node` is a Jac keyword → use `node_bin` in plugin-host code.

### Plugin host (D21)

- Invariant: **JS does not block the first frame** — not "JS never starts at boot."
- Product seam: `session_boot` → `wait_extensions_ready` → `run_turn` with `bridge=`.
- Extension commands run OFF the TUI thread; extension UI requests queue behind the approval overlay.

### Working in `app/`

- `agent-session`-style dependencies flow through `agent/session.jac`; leaf-module changes propagate upward.
- After editing a `.jac` module, check it compiles/lowers before running the dependent test file.
- The TUI paint/layout logic lives in `app/ui/demo_live_shell.jac` (upstream of `tui/shell.jac`); change paint behavior there, not in the shell driver.
- Toolchain: jacup-managed jac 0.37.25 (`~/.local/share/jacup/bin/jac`); NOT `/usr/bin/jac` (stale 0.30.9). The old `vendor/jac` subtree was removed.

## LLVM slice — reuse the shared copy, never fetch a private one

`jac/.llvm-build` in this workspace is a symlink to the single canonical slice at
`~/repos/jaseci/jac/.llvm-build` (pinned LLVM 22.1.8, see `jac/bootstrap/pins.json`).

- Plain `zig build` resolves the slice through the link; `zig build fetch-llvm`
  is a no-op once the marker lib exists. NEVER delete the symlink or fetch a
  private copy — each private `.llvm-build` costs ~3.4G of disk.
- If a build complains the LLVM slice is missing, refresh the canonical copy
  once: `cd ~/repos/jaseci/jac && zig build fetch-llvm` (range-fetch, ~84 MB).
- All local trees pin the same slice (`LLVM-22.1.8-*`). If you bump llvm pins
  in this tree, mirror them in `~/repos/jaseci/jac` so the shared copy is
  refreshed, or pass `-Dllvm-dir` to the build explicitly.
