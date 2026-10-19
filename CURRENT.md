# Jackal — current state (2026-10-18, `main` @ post-`0d02d2a25`)

## CI state (VERIFIED green — run 39258847722, head `dac56075a`)

All six jobs pass: `check`, `agent`, `tui`, `e2e`, `ui`, `other`. First
fully-green run; the three former core-dump suites are fixed (see A2b).
Verified from the uploaded testlogs:

- `constraints/solver` 26/26, `constraints/roundtrip` 36/36,
  `constraints/layout_relations` 7/7, `ui/layout` 90/90 (6.3s),
  `ui/layout_compile` 53/53 (7s), `e2e/tui`/`e2e/integrations` 17/
  `json_protocol` 15/`print_mode` 22/`repl` 15 all pass, `main` 337/337.
- Remaining failures are exactly the quarantine (XFAIL, non-fatal):
  `cordis/core` + `ui/{gates,host,renderer,virtual_terminal,
  demo_complex_shell}`. `ui/renderer` re-confirmed blocked on upstream
  E5090 EdgeRefTrailer (edge traversal lowering) — not fixable by local
  typing, unlike the solver's `any` walls. These stay quarantined until
  upstream lands E5090/E5092/E5093 support (pins documented in
  `app/jac.toml`).

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

## Test infra (2026-10-19, `8e529ea7a` + `b3b6e957e`)

- Suites now run from `app/` (test.sh change): repo-root context broke
  cross-package imports (legacy `tui/`, `lib/`, `dist/` shadow app
  packages; venv `idna/core.py` beats the `app/core` namespace package).
  Three tui suites were silently SKIPPED on CI and are now real:
  overlays 307/307, model_picker_ids 235/235, popup_pick 7/7.
- `tui/*` + `ui.emulated_terminal` pinned server (seam safety, #10213);
  the ui render stack stays native for production. Verified green on CI
  (run 39274861926, all six jobs).
- `tui/harness` quarantined (was silently skipped; crashes under jac
  test driving the native ui stack — blocked on #10213 + ui.model
  upstream walls). Unquarantine when upstream lands seam dispatch.
- `jac x harness` (app/) runs the harness for local iteration.

## Phase C1 done (2026-10-19, `5e1fe4c57`, CI 39325100676)

- `_tick_stream` (tui/runtime.jac) batches streaming rewrites: chunks
  accumulate, one `_rewrite_turn` per 40 ms drain (was per chunk —
  quadratic over the growing body).
- Mock provider streams >160-char answers as ~80-char deltas (was
  exactly 2 chunks, which hid this bug class); short answers unchanged
  (llm.test 228/228).
- e2e "tui streams a 20 KB answer without stalling" (16+1 = 17 passed on
  CI). GOTCHA: wait_for is a raw substring match — wrapped lines split a
  needle; put assertion markers on their own line.

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
