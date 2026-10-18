# Jackal — current state (2026-10-18, `main` @ `0c70f5f0c`)

## CI (run 39175167065, code-identical to HEAD except HANDOFF.md docs)

Green: `check`, `agent`, `tui`, `e2e`. Red: `other`, `ui` (only the A2b
regression + pre-existing quarantine).

- `e2e/tui` 16/16 — PTY TUI boots (`● ready`). The requested TUI fix.
- `e2e/integrations` 16/16, json_protocol / print_mode / repl pass.
- `agent/*` all pass (A3 sidecar fix verified in session, main, keybinding_probe).
- `other/main` 337 passed; `constraints/roundtrip` 36/36.
- Failing: `constraints/solver`, `ui/layout`, `ui/layout_compile` — native
  core dumps, regression from the TUI fix (see A2b below).
- Quarantined (pre-existing, in `scripts/test-quarantine.txt`): `cordis/core`,
  `ui/{gates,host,renderer,virtual_terminal,demo_complex_shell}`.

## Done this session (all pushed to `main`)

1. **A2 — TUI boot crash.** Fixed E1124 (`in` over `any`-typed containers) in
   `app/constraints/solver_dual.jac` (typed local, commit `6af96f49d`) and
   `app/constraints/solver_simplex.jac` lines 349 (`.count`, `0a37f247c`)
   and 366 (`.get is not None`). Line 300 uses a `sorted()+keys()+==` key
   loop (commit `afc38e108`) — see A2b for why.
2. **A3 — sidecar tests.** `app/agent/session_lifecycle.jac`: `_warm_sidecar`
   takes only the cwd string and reads `node_sidecar_decls(plugins.decls)`
   itself (list flow args are E1308-unsendable; `own` locals unbind at run).
   Tests block on the warm future (`wait_extensions_ready(0.0)`) and print
   `plugins.detail` on failure. `app/agent/session.test.jac` updated.
3. **A4 — subagent e2e + read-only auto-approve (behavior change).**
   `app/agent/modes.jac`: new `READ_ONLY_TOOLS` set (read_file, list_dir,
   glob, grep, web_search, web_fetch, list_tasks, jac_check), auto-approved
   in normal mode. `app/agent/agent_tools.jac`: `_subagent_approve`
   auto-approves them in every mode unless blocked. `app/agent/modes.test.jac`
   + `app/agent/approvals.test.jac` updated to the new policy.
   `app/e2e/integrations.test.jac` nesting test runs with `--mode auto-accept`
   (delegation itself stays confirm-gated).
4. **Toolchain.** jac 0.37.25 confirmed newest on the jacup index (local
   default + CI pin). No upgrade available.
5. **Docs.** `HANDOFF.md` A2/A2b + session result recorded.

## A2b — OPEN upstream blocker (human-owned, AGENTS.md rule 5)

Fixing the E1124 at `solver_simplex.jac:300` lets the module lower natively,
then `constraints/solver`, `ui/layout`, `ui/layout_compile` segfault under
`jac test`. Six condition forms all crash identically (typed local, helper
fns, `.get`, `in sorted(...)`, typed bool, key loop) → fault is native
execution of `_solver_add_with_artificial_variable`/module, i.e. a jaclang
native-codegen bug (0.37.25, latest). With the E1124 left in, the module
demotes to server and all pass — but the TUI can't boot. Do NOT quarantine
these (never quarantine your own regression). Next: minimize a repro from
`_solver_add_with_artificial_variable` (Row construction, `dict(row.cells)`,
`_solver_optimize_toward` with `extra: Row | None`) and file upstream to
jaseci-labs/jac. Reverting line 300 to `if art in s.rows` restores solver
green but re-breaks PTY boot.

## Next work (HANDOFF.md Phase B/C)

- Phase B harness scenarios (abort, history, paste, pickers, model picker,
  rendering invariants, markdown, error surfacing, plan mode) in
  `app/tui/harness.test.jac` / `app/e2e/*`.
- Phase C1–C5 (streaming perf, tool-result display, TUI MCP overlay, extension
  key bindings, cold-start noise). C8 OAuth needs user sign-off first.
- Never run suites locally (box has no compute); push and read CI.
  `gh run download <id> -R chess10kp/jackal -n testlogs-<shard> -D <dir>`.
- Commit per change with explicit `git add <paths>` (never `-a`); push to `main`.
