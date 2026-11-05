# Test backlog: Jackal soundness harness

Owner of each item differs: `[us]` fix here, `[upstream]` blocked on
jaseci-labs/jac, `[ops]` CI/tooling change.

Status as of 2026-10-31. Gotchas and runner rules live in [`docs/TESTING.md`](docs/TESTING.md).

## Soundness status (2026-11-01, macOS arm64, vendor 5103ea5cf + hasattr revert)

- **Seal is GREEN.** `cd app && ../jac build` → `Built dist/jackal.jab`
  (25.3 MB gzip / ~65 MB unpacked) with a real native payload:
  `.jac/native/libjackal.dylib` (4.17 MB) over 63 units — the pinned native
  surface plus the `na_stdlib` floors and the jaclang/osp runtime. **No hard
  walls.** The remaining `native seam -- demoting` notes are per-element
  (`layout_compile_*` signature types, renderer/vt test annexes, `oracle_driver`)
  and are allowed by a module-level hard pin.
- **Why the seal was red: the kernel, not the app.**
  [jac#10485](https://github.com/jaseci-labs/jac/issues/10485) root-caused:
  vendor commit `5103ea5cf` added `emit_hasattr`; when the compiler is compiled
  natively for the kernel that body failed to lower and shipped as an
  **`abort()` stub** (`emit_hasattr.__slot` → `abort` in the crash report). Any
  app module containing `hasattr` then aborted the kernel `jc_compile` child —
  no pins or `walker:protect` required (6-line repro in the issue comment).
  The kernel build's own seam note named the culprit: the literal fast path
  used `getattr(node, "lit_value", None)`, a 3-arg `FuncCall` the backend
  refuses. Dropped the fast path (the runtime `strcmp` loop is semantically
  identical) and rebuilt the kernel: `emit_hasattr` now lowers with **no
  demotion**, literal and dynamic `hasattr` return the right answers, and the
  seal is green on the same tree. Vendor branch `fix/native-hasattr-fields` =
  `5103ea5cf` + `383015f8b` (kernel-safe body). Upstream follow-ups filed:
  [#10492](https://github.com/jaseci-labs/jac/issues/10492) (built artifacts
  ship `abort()` stubs silently) and
  [#10493](https://github.com/jaseci-labs/jac/issues/10493) (`jac test` runs
  every imported module's `.test.jac`).
- **Full-suite baseline (macOS, 75 suites)**: the 2026-11-01 09:42 run left
  13 suites red, but all 13 collapsed to two tests in `agent/llm.test.jac`
  that import `httpx` inside the test body while the tree was missing the
  declared `pypi` dependency (so the runner's import-time optional-dep skip
  cannot catch it). `cd app && jac install` fixes it (and did not change the
  other suites' package resolutions). Re-running the whole 75-suite set
  sequentially on the shared box projects 2-4 h, so the delta was verified
  suite-by-suite instead:
  - previously red, now green: `agent/agent_tools`, `agent/auth_env`,
    `agent/chains`, `agent/compaction`, `agent/llm` (232), `agent/session`
    (323), `agent/session_config` (262), `agent/session_turn`,
    `agent/subagents` (248), `main` (360), `tui/model_picker_ids` (239),
    `ui/keybinding_probe` (328);
  - five XPASS quarantine entries removed: `ui/gates` (216), `ui/renderer`
    (146), `ui/host` (39), `ui/virtual_terminal` (15),
    `ui/demo_complex_shell` (237);
  - touched suites: `ui/markup` (25), `ui/screen` (82).
  Only the quarantined `cordis/core` still dies (SIGSEGV, no output);
  `tui/harness` still reports XFAIL (skipped).
  **Caveat:** two isolated `rc=134` aborts in `ui/gates`/`ui/renderer`
  happened only while a second `jac` process was chasing the same suite in
  the same tree; every clean re-run passed (3/3 for the single test, then
  full suites). Treat concurrent `jac test` runs on one tree as unsafe, and
  do not read a bare SIGABRT-with-no-output as a suite regression without a
  clean re-run.
- **Native callable + demotion gaps (found 2026-11-01 chasing `cordis/core`)**:
  - [#10495](https://github.com/jaseci-labs/jac/issues/10495): a **bare
    `Callable`** field/local mis-compiles — the call site ICEs
    (`Type of #1 arg mismatch: i8* != ...`) or segfaults at run time; a call
    to *any* stored callable (`Callable` or `Callable | None`) does not lower,
    so the method demotes. `Callable | None` is the safer annotation (no ICE).
  - [#10496](https://github.com/jaseci-labs/jac/issues/10496): **demotion is
    order-dependent**. A function analyzed before its un-lowerable callee
    stays native and keeps a direct call to the later-demoted function, which
    is a runtime `abort()` stub (`SIGABRT`/`SIGSEGV`, no output). 6-line repro:
    `caller()` declared above a `callee()` that uses 3-arg `getattr`; swapping
    the declarations makes the same program pass.
  - Consequence for `cordis/core`: `Inverse.run`/`Fiber.apply` call stored
    callables → demote; `use()` is declared before `_refresh()` → stays native
    → aborts. The quarantine entry now names both issues instead of saying
    "segfault". `Inverse.fn` was narrowed to `Callable | None` (2 of 6 tests
    now run; the rest still hit the demotion order).
- **Test-annex pins (found 2026-11-01 on Linux x86_64, same vendor)**: the
  seal folds `<mod>.test.jac` into `<mod>`'s native unit, so a hard-pinned
  module whose *tests* import a server module fails the module's pin. That was
  hiding behind the same class as the `ui.screen` wall: `ui.markup`'s annex
  imported `ui.screen.build_main_shell` / `ui.runtime.create_session` and the
  seal aborted with E5093 on `build_main_shell` before any `ui.screen` work.
  Fixed app-side by moving that one cross-context case to
  `app/ui/screen.test.jac` (server-placed owner). Upstream:
  [jac#10490](https://github.com/jaseci-labs/jac/issues/10490) (annexes are
 folded into the hard-pinned unit; no annex-level placement escape). `scripts/seal-pin-guard.mjs`
  now checks the rule statically in CI (`seal-pins` job); see
  [`docs/TESTING.md`](docs/TESTING.md#placement-and-test-annexes).
- **Linux re-read (floor compiler, kernel stale) — historical**: with the
  stale kernel the compiler runs on its bytecode floor and the seal stops
  earlier and differently (`ui/renderer` failing behind a `ui.layout`
  demotion, `NodeEdges` fields erased for type `Variable`). None of that
  reproduces with a current kernel — the lesson is to check
  `jac native status` before reading a seal.
- **Pin semantics**: a module-level hard pin tolerates per-element demotions
  (`ui.layout` demotes `_place_axis`/`compute_layout` and still seals); the
  seal only fails on a hard error (boundary E5093, a native function whose
  only callee is Python-only, …). Do not assert "no demotions" as a proxy for
  "pin honored".

- **Memory (measured 2026-11-01, macOS arm64, release binary)**:
  - **Native artifact (post-seal, the number that matters)**:
    `scripts/mem-profile.sh --idle 8 ../jac run dist/jackal.jab --mode yolo`
    → **127 MB resident on a warm compiler cache**, 243 MB on the first run
    after a kernel rebuild (the parent `jac` recompiles compiler modules; the
    whole tree is sampled). One mock turn completes. That is 5-10× below the
    old source-bundle figure. 127 MB is 1.3× the 100 MB budget; the warm
    number is the honest one for steady state.
  - trivial `jac run` (2-line sleep script): RSS 266 MB, 174 MB of it
    `IOAccelerator` GPU mapping — upstream jac#10487.
  - jackal *source* bundle (pre-native-seal, historical): idle 1.29 GB;
    startup ~20 s CPU; maps `libjac_compiler.dylib` (143 MB) +
    `libjacllvm.dylib` (122 MB) and re-runs native lowering at load ("native
    seam -- demoting ..." in the run log); malloc ~372-424 MB across 1.7 M
    allocations; IOAccelerator 496 MB — upstream jac#10488.
  - 243 MB vs 266 MB for a two-line script says the floor is the runtime
    itself (interpreter + LLVM/kernel mappings), not the app.
  - The 100 MB resident budget therefore needs: (a) a native artifact
    (blocked by #10485), (b) runtime not loading compiler/LLVM (#10488),
    (c) the GPU mapping addressed (#10487).
- **Test gate**: CI has no native-lowering job yet (only `jac check`);
  `mem-profile` job landed in `app-tests.yml`.

## Quarantine triage (see scripts/test-quarantine.txt)

| Suite | Origin | Action |
|---|---|---|
| `ui/gates` | crashed under jac test (native-lowered UI path) | [us] recheck on 0.38.2; if XPASS, delete line |
| `ui/renderer` | same | same |
| `ui/host` | same | same |
| `ui/virtual_terminal` | same | same |
| `ui/demo_complex_shell` | same | same |
| `cordis/core` | tracked-effect assertions fail (core.jac:55/64/84/92) — C0 core predates the native placement switch | [us] real product bug fan-out; split into per-effect testlets before framing an upstream report |
| `tui/harness` | mixed-placement seam crash — jac test dies where native meets Python (jaseci-labs/jac#10213) | [upstream] seam dispatch; unquarantine when landed |

## CI gaps, in priority order

1. **[us] Native lowering gate.** `jac check` runs parse-only; nothing in CI
   proves `app/` seals natively (`../jac build`). Blocked on the runner
 admitting a Zig-built jac (build RAM/time on ubuntu-latest 7 GB is
   unproven). Shipped instead: `scripts/seal-pin-guard.mjs` (the `seal-pins`
   CI job) statically rejects the native->server boundary class that is
   decidable from source. Once the full gate is feasible, add a `native-build`
   job that builds the
   vendored compiler, rebuilds the native kernel, and runs `app/ ../jac
   build`; expected walls: the ~15 `server` pins must stay “seals as pinned”,
   so also assert the MANIFEST placement map matches the pin intent (no
   silent demotions).
2. **[us] Compiler currency probe.** CI pins `JAC_VERSION` (0.38.2) forever;
   a stale kernel or old release drifts silently (dev-box saw a stale-kernel
   bytecode fallback this week). Add a cron job that interns the latest
   release, runs the tame shards, and opens a PR bumping the pin when green.
3. **[us] Strict memory budget.** `mem-profile` CI job (scripts/mem-profile.sh)
   gates on a provisional resident budget until native-only runtime; then +
   tightens the strict 100 MB step.
4. **[ops] XPASS reaper.** XPASSes are reported but not acted on; a manual
   deletion policy is fine, but reviewing the quarantine list every milestone
   is now an explicit AGENTS.md milestone item.

## Coverage gaps (feature-frontier tests missing)

- CLI e2e (`agent/cli.jac`) has a unit suite only; no e2e against the real
  process exit codes/`--json` surfaces.
- MCP config parsing is covered (`agent/mcp`), but connection *failure
  paths* (dead port, bad config) are only implicit through the TUI.
- Auth/keyring: `agent/auth` + `agent/auth_env` suites exist; the missing
  layer is an e2e in a controlled HOME.
- Plugin bridge hooks run in-process (`plugin_hooks_events`); no e2e with
  `app/plugin_host` fixtures.
