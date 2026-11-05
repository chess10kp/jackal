# All-native / no-Python closure scope

**Status:** scope, not completion evidence (2026-11-05)

Jackal's end state has no Python runtime or Python source anywhere in the
Jackal/Jac toolchain or app workflow. This includes the compiler used to build
and launch Jackal. “It is written in Jac” or “it embeds JacPython instead of
stock CPython” does not satisfy the goal. The compiler, product, fixtures, and
test runner must execute without a Python interpreter, Python bytecode, Python
packages, or Python-only codespace.

This scope does not remove the explicitly supported Node extension host. Node
is an intentional Pi-compatibility process boundary. Node-based test fixtures
are temporary, though: app tests and their fixtures must run through the
native Jac test path.

## Closure gates

These gates are ordered by dependency. Work on later app seams can continue as
focused source/lowering work, but cannot count as end-to-end closure until gates
0 and 1 produce trustworthy compiler and graph evidence.

| Gate | Scope | Current seam | Closure evidence |
|---|---|---|---|
| 0. Python-free Jac compiler | Replace the embedded JacPython/CPython runtime and Python-tier compiler execution with a native compiler executable and native compiler runtime. Remove CPython source archives, JacPython generation/runtime payloads, Python-only compiler functions, Python bytecode fallbacks, and Python-dependent bootstrap/release steps. Port or delete Python source across the compiler repository, including bootstrap, launcher/import hooks, compiler entry points, tests/fixtures, and examples; no Python-source exceptions are assumed. Remove or replace Python interop itself if it requires a Python runtime. Preserve Jac source compilation and project preparation. | The shipped `jac` binary embeds JacPython/libpython. The active nested `vendor/jac` checkout has 91 tracked `.py`/`.pyc` paths: 26 compiler/runtime/bootstrap/launcher files, 60 tests and fixtures, 3 Python helper scripts, and 2 Python examples. They include `jac/_jac_finder.py`, `jac/bootstrap/python/{finalize,prepare_native,smoke}.py`, Python importer hooks and compiler entry files, interop fixtures, and compatibility tests. A fresh post-cleanup build successfully linked a 196-unit native kernel after 1,279 seconds; it clears the `BaseOf` archwire diagnostic but emitted 29 Python-only demotions. They group into: compiler pass schedules (`list[type[CompilerPass]]` literals); native backend helpers (`_emit_intrinsic_list_data`, C-entry selection); unit-product and cache serialization (`InteropContext`, comprehensions, dict updates, list construction); placement cache/report helpers; frontend deep-copy/repr (`__dict__`, `__new__`, `super`); and ES backend entry generation. The `is_secret_file` suffix-tuple call was rewritten as a loop, and backend checks were simplified to remove unsupported `getattr`/comprehension shapes. The follow-up kernel analysis first exposed three `Unknown`-to-dict type errors in the cache-record rewrite; those assignments now use typed record defaults. That build could not be completed: global disk space fell to 118 MB while compiler caches were being written. After stopping the run, 468 MB was available; the shared Jac cache reports 85.7 GB of module JIR and 12.1 GB of runtime artifacts, all currently inside retention windows. The native kernel is stale against current source; the latest edits do not yet have a clean native rebuild, and demotions remain. | From a clean checkout, bootstrap, run, and build with Python absent. Inspect the resulting compiler and loaded libraries: no Python interpreter, bytecode VM, `.py` source/runtime modules, or Python payload. Every compiler source unit required by CLI/build/test dispatch has native execution or a non-Python native implementation; all remaining Python files and compatibility fixtures are gone. |
| 1. Reliable native prepare and graph accounting | Make native-only preparation deterministic; emit a current manifest that records product roots and each test root separately, including transitive imports, dynamic imports, test annexes, selected codespace, and lowered/native execution. Distinguish unreachable dev/debug modules from product modules using compiler-derived reachability. | The last seal is stale (147 entries, tagged `cpython-314`). Current source pin ledger is 24 server pins (6 UI, 18 TUI); implicit demotions and same-stem test annex merges are not captured by static scans. A previous fresh compiler attempt hit a dylib initializer crash ([jac#10590](https://github.com/jaseci-labs/jac/issues/10590)); archwire import fallout is reported in [jac#10596](https://github.com/jaseci-labs/jac/issues/10596). | Fresh-kernel build produces manifests for `main.jac`, `tui/shell.jac`, and every `*.test.jac`; manifests have zero server/Python placements and agree with runtime tracing. No stale seal or source-only pin count is used as proof. |
| 2. Native ABI and runtime floors | Close the shared ABI and native standard-library surface needed by app roots: imported native function calls and type layouts; filesystem/path/env/JSON; Unicode and streams; HTTP/TLS/URL/IP; subprocess spawn/wait/capture/cwd/env/timeout/kill; threading, locks, events, and channels; terminal/TTY APIs. The native implementation may use Jac, Zig, or a narrow platform ABI, but cannot call into Python. | Imported native function ABI is still reported at [jac#9145](https://github.com/jaseci-labs/jac/issues/9145#issuecomment-6648729118). Darwin subprocess has basic spawn/wait/capture evidence only. Web tools still depend on Python URL parsing/IP classification. Cancellation, contention, redirect/SSRF, and Linux behavior lack root-level proof. | Native consumer probes and integration tests pass on macOS and Linux with Python removed from PATH and loader environment. Every used floor operation has a native implementation and failure/cancellation semantics. |
| 3. Headless agent closure | Lower `main.jac` through auth, project/session config, command dispatch, model state, registry/tool calls, session boot/disposal/turn, provider hooks, MCP, and optional extension bridge. Preserve extension support at the documented Node subprocess boundary. | Current headless frontier reaches `session_config`, `session_commands`, then session lifecycle/turn. Concrete blockers include imported registry calls, nested MCP config maps/optionals/callback-lock state, model globals/AtomTrailer access, boot composition (mode, tool registration, MCP, prefs, bridge/sidecar), provider hooks, and imported `PluginBridge` object layouts. | Clean native `main.jac` artifact runs line and JSONL modes; mocked authenticated tool turn, MCP attach/call/restart, cancellation, and configured-extension lifecycle complete with zero server/Python placement. |
| 4. UI / OSP closure | Lower the product object graph together: runtime/session records, model/mutation, events/walkers, screen, input, layout, renderer, transcript, and lifecycle/disposal. Keep demos, gates, inspect, and harness roots separately classified unless reached by a supported product/test root. | `ui.screen` and `ui.input` are server-pinned. Known seam classes include cross-module type layout/construction, `jid()` identity, bound edges, unary expressions, callable fields, protected walker dispatch, and event/session ABI boundaries. `walker:protect` currently reaches a kernel prepare abort ([jac#10485](https://github.com/jaseci-labs/jac/issues/10485)). | Native app executes construction, input/event handling, mutation, render, resize, and disposal with stable JID/state behavior; the product graph contains no server placement. |
| 5. TUI loop closure | Move `tui.shell` and its 18 currently pinned TUI modules onto the native UI and agent graph. Close terminal lifecycle, input normalization, resize, queue/worker handoff, overlays/pickers, command routing, streaming, approvals, cancellation, and restoration. | The earlier `queue` and TTY-detection walls have native implementations. The remaining shell dependency graph is still server-pinned and crosses `agent.session`, UI screen/runtime, renderer/input, resize, and TUI composition. | A clean native TUI artifact passes PTY/virtual-terminal acceptance for first frame, streaming, approval, cancellation, resize, Unicode/paste, and terminal restoration. |
| 6. Native test execution and fixtures | Replace server-dispatched `jac test` with native test discovery, setup/teardown, assertions, subprocess invocation, and reporting. Port Node `.mjs` MCP/SSE test servers to native Jac fixtures; remove Python and Node fixture launch requirements from app tests. Keep fixtures isolated from product import units instead of relying on annex merges. | `jac test` currently runs in server codespace and ignores placement pins. MCP/SSE fixtures are Node `.mjs`; test annexes can pollute same-stem product lowering. Python fixtures, `sys.executable`, Kiwi oracle, and inert Python package marker have already been removed. | Every app test and fixture runs in native codespace through the native test runner with Python absent; fixture process/runtime requirements are explicit and no test-only import changes a product module's placement. |
| 7. Retire pins and prove artifacts | Remove all temporary server pins only after root-specific builds and runtime checks pass. Cover both product roots and every test root, then run repository-wide scans over tracked, ignored, generated, vendored, release, container, and CI paths. | `app/jac.toml` has 24 server pins: product-reachable `ui.input`, `ui.screen`, and the pinned TUI shell graph, plus debug/test entries that still need compiler reachability classification. The 147-entry seal is stale; the latest kernel rebuild exited 1 and `jac native status` still reports stale/missing compiler artifacts. | Zero server pins and zero implicit server demotions across supported roots; clean product/test artifacts execute natively; repository artifact/source/dependency scans find no Python runtime, `.py` source, Python bytecode, package install, or Python invocation. |

## Execution order and parallel work

1. **Unblock gate 0 and gate 1 together.** Finish or diagnose the active kernel
   build, resolve clean compiler startup, remove Python-tier compiler paths,
   and implement the root/annex placement manifest. Do not use old seals to
   guide app pin retirement.
2. **Work gate 2 independently with minimal executable probes.** Prioritize
   imported native calls/type layouts, subprocess completion semantics, URL/IP
   operations, and the terminal/thread APIs that app roots consume. Each probe
   must execute as native code, not merely lower into a library.
3. **Close headless and UI graphs as separate root slices.** Headless agent
   work can progress alongside OSP/compiler work. Remove the current pins only
   after an importing root builds and runs natively.
4. **Close TUI after the shared UI graph.** Preserve a single typed channel
   contract between the native shell and agent worker; validate terminal
   restoration on failures and cancellation.
5. **Build native test dispatch and fixtures against the same compiler/ABI.**
   Product source tests can be prepared earlier, but native test acceptance
   waits for gate 0 and must account for all test annexes.
6. **Run artifact proof and repository audit last.** Repeat the clean build and
   runtime checks on macOS and Linux; inspect artifacts and loaded libraries;
   scan tracked and untracked source, ignored vendor/build outputs, release
   packaging, containers, and CI commands.

## Explicit non-closure shortcuts

- Selecting a Python/server codespace, retaining an embedded JacPython runtime,
  or moving a function behind a Python adapter.
- Calling a Jac library build a root closure without testing imported calls and
  native runtime behavior.
- Counting an explicit `native` pin as proof that the sealed/runtime placement
  is native.
- Treating an empty package lock or removal of app `.py` files as proof that
  the compiler/runtime has no Python.
- Treating Node fixtures as final all-native test fixtures.
- Retiring pins based on stale manifests or static import scans alone.
