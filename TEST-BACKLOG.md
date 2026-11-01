# Test backlog: Jackal soundness harness

Owner of each item differs: `[us]` fix here, `[upstream]` blocked on
jaseci-labs/jac, `[ops]` CI/tooling change.

Status as of 2026-10-31. Gotchas and runner rules live in [`docs/TESTING.md`](docs/TESTING.md).

## Soundness status (2026-11-01, macOS arm64, vendor 5103ea5cf)

- **Native seal**: the app tree reaches `Built dist/jackal.jab` when explicit
  `"x" = "native"` pins that cannot lower are removed (default-native modules
  demote softly). With the pins in place the sole hard wall is `ui.screen`
  (E5106 private-bridge to `InsertText`/`Submit`/`Cancel` from server-pinned
  `ui.events`; E5093 event/UiSession class boundary). The documented
  `walker:protect` workaround trips a kernel prepare abort —
  [jaseci-labs/jac#10485](https://github.com/jaseci-labs/jac/issues/10485).
  Tuple-union annotation collapse is
  [#10480](https://github.com/jaseci-labs/jac/issues/10480) (worked around).
- **Test-annex pins (found 2026-11-01 on Linux x86_64, same vendor)**: the
  seal folds `<mod>.test.jac` into `<mod>`'s native unit, so a hard-pinned
  module whose *tests* import a server module fails the module's pin. That was
  hiding behind the same class as the `ui.screen` wall: `ui.markup`'s annex
  imported `ui.screen.build_main_shell` / `ui.runtime.create_session` and the
  seal aborted with E5093 on `build_main_shell` before any `ui.screen` work.
  Fixed app-side by moving that one cross-context case to
  `app/ui/screen.test.jac` (server-placed owner). Upstream:
  [jac#10490](https://github.com/jaseci-labs/jac/issues/10490) (annexes are
  folded into the hard-pinned unit; no annex-level placement escape). `scripts/seal-pin-guard.py`
  now checks the rule statically in CI (`seal-pins` job); see
  [`docs/TESTING.md`](docs/TESTING.md#placement-and-test-annexes).
- **Linux re-read (floor compiler, kernel stale)**: with the stale kernel the
  compiler runs on its bytecode floor, and the seal stops earlier and
  differently than on the mac: `ui/renderer` fails because `ui.layout`
  demotes, which cascades from `ui/layout_compile_model` erasing all four
  `NodeEdges` fields ("Native lowering failed for type 'Variable'"; `Variable`
  is a trivial `obj` in native-pinned `constraints.algebra`). The exact
  erasure trigger is unresolved — the floor path may itself be the difference
  (`jac native status kernel` said `stale: na_ir_gen_pass.jac changed`), so
  re-read the seal on the mac's built kernel before filing. #10485 did not
  reproduce on the floor, which is consistent with it being a kernel-path
  abort; that is not a disproof.
- **Pin semantics are not all-or-nothing on the floor**: hard-pinned
  `ui.layout` demoted `_place_axis`/`compute_layout` to Python-only without a
  `FAIL (native unit did not lower)` line, while `ui/renderer` did fail once
  `_run_layout`'s only callee was Python-only. So a module-level hard pin can
  survive per-function demotions and still report success; the `jac.toml`
  "hard requirement" wording is mac-kernel-verified and should be re-checked
  on the rebuilt kernel before being relied on for CI assertions.

- **Memory (measured 2026-11-01, macOS arm64, release binary)**:
  - trivial `jac run` (2-line sleep script): RSS 266 MB, 174 MB of it
    `IOAccelerator` GPU mapping — upstream jac#10487.
  - jackal sealed bundle: idle 1.29 GB; startup ~20 s CPU; maps
    `libjac_compiler.dylib` (143 MB) + `libjacllvm.dylib` (122 MB) and
    re-runs native lowering at load ("native seam -- demoting ..." in the
    run log); malloc ~372-424 MB across 1.7 M allocations; IOAccelerator
    496 MB — upstream jac#10488.
  - The artifact was a **server-only source bundle** (verified manifest:
    139/139 server, 221 `.jac` files, no native payload), so this is the
    plain runtime cost, not a native artifact.
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
   unproven). Shipped instead: `scripts/seal-pin-guard.py` (the `seal-pins`
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
