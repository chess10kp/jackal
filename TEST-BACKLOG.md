# Test backlog: Jackal soundness harness

Owner of each item differs: `[us]` fix here, `[upstream]` blocked on
jaseci-labs/jac, `[ops]` CI/tooling change.

Status as of 2026-10-31. Gotchas and runner rules live in [`docs/TESTING.md`](docs/TESTING.md).

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
   unproven). Once feasible, add a `native-build` job that builds the
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
