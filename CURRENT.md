# Jackal — current state (2026-10-18, `main` @ post-`0d02d2a25`)

## CI state at this snapshot (pushed; read the run before branching)

Expected green: `check`, `agent`, `tui`, `e2e`, `ui`, `other` — the three
former core-dump suites are fixed (see A2b). Only pre-existing quarantine
remains (`cordis/core`, `ui/{gates,host,renderer,virtual_terminal,
demo_complex_shell}`). VERIFY on the first run after `0d02d2a25` — the notes
below were written before that run came back.

- `e2e/tui` 16/16, `e2e/integrations` 16/16, json_protocol / print_mode /
  repl pass (unchanged by the solver restructure; layout is now fully native).
- `constraints/solver` 26/26, `constraints/layout_relations` 7/7,
  `constraints/roundtrip` 36/36, `ui/layout` 90/90, `ui/layout_compile`
  53/53 — verified locally on fresh caches, zero demote notes.

## Done this session (pushed to `main`)

1. **A2b SOLVED — the "native codegen segfault" was a jac-test seam crash.**
   Under `jac test`, native-lowered callers reaching Python-demoted functions
   hit unwired seam slots (NULL call / abort, output swallowed). `jac run`
   demotes callers, `jac build` rejects the graph; `jac test` does neither.
   That is why six condition forms at `solver_simplex.jac:300` all crashed
   identically. Filed upstream with a 2-file repro:
   [jaseci-labs/jac#10213](https://github.com/jaseci-labs/jac/issues/10213).
2. **Constraints chain is now fully native.** `solver_journal.jac`,
   `solver_simplex.jac`, `solver_dual.jac` are folded into
   `constraints.solver` via the new `app/constraints/solver.impl.jac` impl
   annex (same module → `Solver` can be named without an import cycle); every
   former `s: any` parameter is `s: Solver`; `factory: any` params and the
   `as Solver` cast are gone; the artificial-variable membership check is back
   to `art in s.rows`. Zero demotions — verified via compile output and by the
   suites above passing on fresh caches.
3. **A2/A3/A4 from the previous session** (TUI boot, sidecar tests, subagent
   e2e + read-only auto-approve) — already in; see git log `8cf8e0db5`..
   `afc38e108` and HANDOFF.md.

## Standing rule (new, learned the hard way)

After ANY change to a native-pinned module, read the compile/test output for
`native seam -- demoting` notes. One new demotion in a natively-called chain
reintroduces the A2b crash under `jac test` until upstream fixes seam
dispatch (see #10213). Suites must never be quarantined for this — fix the
demotion instead.

## Next work (HANDOFF.md Phase B/C)

- Phase B harness scenarios (abort, history, paste, pickers, model picker,
  rendering invariants, markdown, error surfacing, plan mode) in
  `app/tui/harness.test.jac` / `app/e2e/*`.
- Phase C1–C5 (streaming perf, tool-result display, TUI MCP overlay, extension
  key bindings, cold-start noise). C8 OAuth needs user sign-off first.
- Seal (`jac build`) is still red and pre-existing: aborts at
  `ui/renderer.jac` (pinned native, E5090 EdgeRefTrailer); at the pre-restructure
  HEAD it aborted earlier inside the old solver graph. CI gates on
  `jac check`, not seal — seal-green is its own workstream (renderer/terminal/
  model E5090/E5092 walls, all documented in `app/jac.toml` pins).
- Never run full suites locally (box has no compute); push and read CI.
  `gh run download <id> -R chess10kp/jackal -n testlogs-<shard> -D <dir>`.
- Commit per change with explicit `git add <paths>` (never `-a`); push to `main`.
