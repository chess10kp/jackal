# All-native / no-Python closure scope

**Status:** scope, not completion evidence (2026-11-06)

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

## Upstream review slices

The oversized compiler change in [jac#10604](https://github.com/jaseci-labs/jac/pull/10604)
is closed. Its non-generated source changes are split across these focused PRs;
the slices can be reviewed and landed independently:

| PR | Seam |
|---|---|
| [#10586](https://github.com/jaseci-labs/jac/pull/10586) | Darwin subprocess and inherited environment support |
| [#10587](https://github.com/jaseci-labs/jac/pull/10587) | Native tempfile directory creation |
| [#10632](https://github.com/jaseci-labs/jac/pull/10632) | Native project identity and preparation |
| [#10633](https://github.com/jaseci-labs/jac/pull/10633) | Compiler lowering and manifests |
| [#10634](https://github.com/jaseci-labs/jac/pull/10634) | Native build cache and dependency deduplication |
| [#10611](https://github.com/jaseci-labs/jac/pull/10611) | Placement pin diagnostic fast path |
| [#10612](https://github.com/jaseci-labs/jac/pull/10612) | Native module interop mirroring |
| [#10613](https://github.com/jaseci-labs/jac/pull/10613) | Native HTTP and urllib support |
| [#10614](https://github.com/jaseci-labs/jac/pull/10614) | Native threading primitives |
| [#10641](https://github.com/jaseci-labs/jac/pull/10641) | Remove server fallbacks from native unit compilation |
| [#10642](https://github.com/jaseci-labs/jac/pull/10642) | Advance compiler import closure |
| [#10643](https://github.com/jaseci-labs/jac/pull/10643) | Represent native pass schedules as values |
| [#10644](https://github.com/jaseci-labs/jac/pull/10644) | Match JacPython's native compile ABI |
| [#10645](https://github.com/jaseci-labs/jac/pull/10645) | Sync sealed JIR with linked native interfaces |

The earlier compiler closure PRs [#10604](https://github.com/jaseci-labs/jac/pull/10604)
and [#10610](https://github.com/jaseci-labs/jac/pull/10610) are closed; their
work is represented by the focused PRs above. Together the open slices account
for the original change's non-generated source paths. They are review slices,
not closure evidence for the Python-free toolchain.

## Closure gates

These gates are ordered by dependency. Work on later app seams can continue as
focused source/lowering work, but cannot count as end-to-end closure until gates
0 and 1 produce trustworthy compiler and graph evidence. Gate 0 exceeds the
current upstream kernel-only plan ([jac#10471](https://github.com/jaseci-labs/jac/issues/10471)),
which still relies on JacPython; the Python-free compiler end state is tracked
at [jac#10601](https://github.com/jaseci-labs/jac/issues/10601). The specific
native lowering gap in the compiler's statically known pass-class schedule is
tracked at [jac#10600](https://github.com/jaseci-labs/jac/issues/10600).

There are two independent kinds of closure:

1. **Native app closure:** every supported app and test root executes in native
   codespace, with no server placement or silent demotion.
2. **Python-free toolchain closure:** the Jac compiler used to build and launch
   Jackal has no Python interpreter, Python bytecode backend, Python source
   runtime, or Python-only bootstrap path.

Both are required. App placement work can proceed while the toolchain is being
replaced, but it cannot establish the final goal by itself. Likewise, a native
compiler kernel does not prove that `jac run`, `jac build`, or `jac test` avoid
the Python tier: the current executable still carries JacPython/libpython.

| Gate | Scope | Current seam | Closure evidence |
|---|---|---|---|
| 0. Python-free Jac compiler | Replace the embedded JacPython/CPython runtime and Python-tier compiler execution with a native compiler executable and native compiler runtime. Remove CPython source archives, JacPython generation/runtime payloads, Python-only compiler functions, Python bytecode fallbacks, and Python-dependent bootstrap/release steps. Port or delete Python source across the compiler repository, including bootstrap, launcher/import hooks, compiler entry points, tests/fixtures, and examples; no Python-source exceptions are assumed. Remove or replace Python interop itself if it requires a Python runtime. Preserve Jac source compilation and project preparation. | The shipped `jac` binary embeds JacPython/libpython. The active nested `vendor/jac` checkout has 91 tracked `.py`/`.pyc` paths: 26 compiler/runtime/bootstrap/launcher files, 60 tests and fixtures, 3 Python helper scripts, and 2 Python examples. They include `jac/_jac_finder.py`, `jac/bootstrap/python/{finalize,prepare_native,smoke}.py`, Python importer hooks and compiler entry files, interop fixtures, and compatibility tests. Historical pre-`PassKind` evidence includes a 196-unit native-kernel link with 29 Python-only demotions and a later cache write stopped by `ENOSPC`; neither describes current source. The class-valued pass schedule has been replaced by an explicit `PassKind` dispatcher; the `sem_def_match_pass.jac` re-entry is guarded. On 2026-11-05, exact-source kernel prefixes of 10, 30, and 40 units completed (89.2s / 4.0 GB, 92.5s / 4.3 GB, and 111.0s / 4.6 GB). On 2026-11-06, a fresh 60-unit prefix completed in 298s with 201 analyses, 115 lowering requests, 100 nested dependency lowers, and 6.7 GB peak RSS. A 100-unit attempt with the current compiler work did not reach its bound: after 11m25s it had analyzed 193 distinct modules and issued 1,684 lower requests, repeating `primitives_native.jac` 261 times and `region_abi.jac` 260 times. The later attempt was stopped for structural work on dependency ordering. These are bounded-prefix measurements only; there is no current full-kernel link or complete demotion report. | From a clean checkout, bootstrap, run, and build with Python absent. Inspect the resulting compiler and loaded libraries: no Python interpreter, bytecode VM, `.py` source/runtime modules, or Python payload. Every compiler source unit required by CLI/build/test dispatch has native execution or a non-Python native implementation; all remaining Python files and compatibility fixtures are gone. |
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

## Work batches

These batches turn the gates into reviewable deliverables. A batch closes only
when its stated evidence is recorded; source edits or successful lowering alone
do not close it.

| Batch | Deliverable | Scope boundary | Exit evidence |
|---|---|---|---|
| A. Reproducible compiler kernel | A current native kernel built from the exact compiler source revision, with a machine-readable demotion/error report. | Fix compiler startup/build failures first; then close kernel demotions by shared operation. Start with the pass schedule (`PassKind` or full native class-object support), then native backend helpers, cache/product serialization, placement/reporting, frontend reflection, and ES generation. Do not rewrite the entire compiler before the report identifies actual blockers. | Clean kernel build; zero Python-only demotions for kernel-required modules; compiler pass order and diagnostics match the established pipeline. |
| B. Root and annex ledger | A compiler-generated closure manifest for `main.jac`, `tui/shell.jac`, and every app test root. | Keep product dependencies and same-stem test annex dependencies distinct. Record dynamic imports, actual selected codespace, and fallback reason, not only source pins. | Current manifests agree with runtime placement traces and are tied to the compiler/source revision that produced them. |
| C. Python-free compiler and bootstrap | A Jac compiler artifact that prepares and executes Jac without a Python payload. | Replace the Python-emitting bootstrap and Python-tier CLI/import hooks; remove the JacPython/CPython payload, Python bytecode path, Python interop/runtime, and Python-only build/test/release code. Decide which Python interoperability/package features are removed versus reimplemented natively. | From clean source, build and run `jac` with Python absent; inspect dependencies and loaded libraries; no Python source/runtime/bytecode in compiler artifacts or required source closure. |
| D. Native runtime floors | A cross-platform native API contract for the app's imported calls and OS services. | Prioritize cross-module function/type ABI, process lifecycle, threads/channels/locks, terminal I/O, path/env/JSON/Unicode, and URL/IP/HTTP/TLS according to the root manifests. Replace Python URL parsing and classify each capability as Jac, Zig/platform ABI, or removed feature. | Small native consumers and failure/cancellation probes pass on macOS and Linux without Python. |
| E. Product roots | Native headless, OSP/UI, then TUI artifacts with root-specific runtime evidence. | Headless: session/config/registry/provider/MCP/bridge lifecycle. UI: shared records, events/walkers, input, screen, render/layout. TUI: shell composition, worker handoff, approvals, resize, cancellation, restoration. Retire pins only inside the root slice that has passed. | Each supported root builds and executes with zero server placements or demotions; TUI acceptance includes PTY/virtual-terminal behavior. |
| F. Native test system | Native discovery and execution for every app test and its fixtures. | Separate test roots from product units; implement test lifecycle/reporting and native Jac process fixtures; remove Node fixture launch dependencies from app tests. The supported Node extension host remains a product subprocess boundary, not a test-runner dependency. | Every app test runs through native `jac test` with Python absent; product manifests are unchanged by test-only imports. |
| G. Release proof | A clean, auditable no-Python Jackal release. | Remove obsolete Python build/install/release paths and scan source, dependencies, generated files, ignored vendor snapshots, release artifacts, CI, and launch scripts. | Reproducible clean build/run/test on macOS and Linux; dependency/load inspection finds no Python runtime, and source/workflow scans find no Python implementation or invocation. |

Batch dependencies: A and B establish trustworthy compiler and graph evidence.
C depends on A; D can progress from B's root imports while C is underway. E
depends on B and D, with UI before TUI. F depends on C and D and validates each
test root from B. G closes after C through F. App lowering and runtime-floor
work can progress before the compiler rewrite finishes, but does not count as
end-to-end completion.

## Seam register and first work batches

The gates above describe acceptance. This register identifies the concrete
seams to close first and prevents app pin work from being mistaken for compiler
or runtime closure.

| Order | Seam | Owning area | Work to close it | Depends on / proof |
|---|---|---|---|---|
| 0 | Imported symbols are not consistently exported across Jac compilation units | `app/agent`, `app/ui`, `app/tui`, `app/constraints`, and compiler module ABI | Jac modules use explicit public declarations for definitions imported by another compilation unit. A static import/declaration scan found 311 private function/global declarations and 416 private type declarations in the app import graph; these were promoted in the current source work. A follow-up scan found 25 additional private declarations in skills, logging, tool-spec, and subagent imports; those are now promoted too. Keep this as an interface invariant and make the compiler report missing exports at the importing edge, rather than discovering them as runtime `cannot import name` errors. | Gate 1. Fresh native lowering and root execution must resolve every imported symbol with the same exported name and type layout; import-graph scan reports zero private imported declarations. |
| 1 | Native kernel expansion repeats compiler graph resolution | `vendor/jac` compiler loader, module resolver, pass dispatcher, native kernel scheduler | Keep the explicit `PassKind` schedule and import guards. A clean 60-unit prefix now completes, but the 100-unit trace repeats core native/ES modules across the import closure. Implement native interface products and topological lowering so each unit is analyzed after its dependencies and lowered once; keep source-key negative results only for clean modules that emit no native interface. | Gate 0. The 100-unit prefix must reach its requested count with bounded repeated lower work and a complete refusal report, then the full kernel must link. The 60-unit timing is a bounded progress result, not a current compiler artifact. |
| 2 | Pass schedule stores compiler classes as runtime values | `compiler/driver/pipeline.jac`, pass contracts and native dispatcher | The class-valued schedule has been converted to a 46-value `PassKind` enum with explicit scheduled and early-pass dispatch. Static source comparisons find no pass-order differences across 27 product schedules and no differences in 46 explicit pass contracts (required/provided facts and `kernel_safe`). Keep class objects out of runtime schedules; update the enum, contract mapping, dispatch, and tests together for each new pass. | Gate 0. These are source-level parity checks only. A current native compiler rebuild and the schedule/early-pass suites must pass before this seam is closed. |
| 3 | Compiler helper and product paths still depend on unsupported dynamic shapes | `compiler/backends/native`, `compiler/driver/unit_products`, placement/cache/report, frontend | Use the fresh demotion report to group remaining failures by shared missing operation. Initial known groups are LLVM type inspection/C-entry selection, product/cache serialization, placement reporting, frontend deep-copy/repr, and ES entry generation. Add native implementations or replace reflection with typed dispatch at the owning API. | Gate 0. Each helper lowers in the kernel and is exercised through a compiler command; source `jac check` alone does not close it. |
| 4 | Python is still part of the compiler architecture and bootstrap | `jaclang/bootstrap`, launcher/importer, compiler source-products and Python interop | Choose the native compiler's supported input universe, then remove Python execution and source compilation paths from bootstrap, CLI, compiler sessions, imports, interop, test tooling, packaging, and release. Port Jac-authored tooling first; replace or delete Python-only facilities and their fixtures. | Gates 0 and 6. Clean bootstrap/run/build/test with Python executables and libpython unavailable, followed by source/artifact inventory. This is the largest workstream and must not be represented as a cleanup of the 91 tracked Python paths alone. |
| 5 | Native runtime ABI and standard-library coverage | `vendor/jac` native runtime/stdlib; `app/agent`, `app/ui` consumers | Drive runtime work from the app root imports: imported function ABI and cross-module type layouts; subprocess/thread/channel/terminal behavior; path, JSON, URL/IP, Unicode, HTTP/TLS. Replace Python URL parsing/IP checks and close native cancellation/error behavior where product code relies on it. | Gate 2. Small native consumer programs must link and run on macOS and Linux with Python absent; library lowering by itself is insufficient. |
| 6 | App module placement and cross-code-space object boundaries | `app/ui`, `app/agent`, `app/tui`, `app/jac.toml` | Close the UI graph before the shell graph. First settle shared `UiNode`/`UiSession`/event/walker layouts and `ui.screen` dispatch; independently diagnose the `ui.input` native crash. Then promote headless agent roots and TUI modules in root-sized slices, resolving imported constructors and callback/object boundaries where they occur. | Gates 1 and 2. The current 24 server pins are 6 UI and 18 TUI; pin retirement needs a current root manifest and executable root probes. Existing explicit native module pins are work targets, not proof of native runtime closure. |
| 7 | Native test discovery, annexes, and fixtures | compiler test command; `app/**/*.test.jac`; `app/e2e/` | Implement native test discovery and dispatch, setup/teardown, assertions, process fixtures, and reports. Give each test its own recorded root and dependency closure; stop folding test-only imports into product units. Port Node MCP/SSE fixtures to Jac-native process fixtures once subprocess capabilities are available. | Gates 0–2. Run every app test root through the native runner with Python absent; verify product roots independently of test annexes. |
| 8 | Release and artifact proof | launcher/bootstrap, packaging/CI, root audit scripts | Build and launch from a clean checkout; inspect executable dependencies and runtime-loaded libraries; scan source, generated artifacts, release bundles, container/CI files, and ignored vendor trees. Remove obsolete Python compatibility claims and scripts only when the corresponding native replacement is covered. | All previous gates. Reproduce on macOS and Linux; preserve command output and artifact hashes as closure evidence. |

### Immediate next steps

1. Implement the dependency-interface/topological lowering step in seam 1 while
   keeping the `PassKind` schedule and its source-level order/contracts.
2. Rerun the 100-unit native kernel prefix and capture its complete
   diagnostic/demotion report. Do not use an old kernel or cached seal as
   current evidence.
3. Define and generate the root/annex ledger for `main.jac`, `tui/shell.jac`,
   and every test root. Keep requested placement, actual placement, and demotion
   reason separately visible; preserve the cross-unit export invariant in it.
4. Use that ledger to drive runtime-floor probes and close product roots in this
   order: headless agent, shared UI, TUI. Track Python-free compiler/bootstrap
   replacement as its own deliverable throughout; no app milestone closes the
   overall goal without it.

### Current app build evidence (2026-11-06)

A fresh `cd app && ../jac build` processed 151 app Jac files and 480 native
units. The prior `_parent_dir` native ICE and the test-annex self-import were
removed by giving the path shim a `str` parameter and using annex symbols
directly. The launcher executable check now uses `shutil.which`; subagent file
discovery has a fixed native predicate instead of a dynamic callback. The
three affected annexes and `run.jac`/`subagents.jac` pass `jac check`.

The build still ends before producing a seal: the staged app and the source
tree both contribute `constraints/algebra.jac` under the same native unit
prefix. This is tracked upstream in [jac#10623](https://github.com/jaseci-labs/jac/issues/10623).

Independent `--native --lib` builds now produce native libraries without seam
demotions for the interaction queue (8 units), plugin bridge I/O (27), UI
transport (32), hooks (32), extension features (33), extension loading (34),
and registry (33). The fake host callbacks and correlation/UI records now
have typed Jac layouts; extension event maps use typed access at the native
boundary. These leaf builds do not prove the combined `main.jac` or TUI graph.
The full build still has other agent/session and test-annex demotions, and its
link-plan collision prevents current full-root accounting. Fix that collision
and regenerate the root ledger before claiming zero demotions.

The checkpoint store now also lowers as a 34-unit native library with no seam
demotions, including its test annex. It uses the native clock and timestamp
formatting path, typed file streams, recursive directory sizing, and explicit
timestamp insertion ordering. This is leaf lowering evidence only; the test
suite was not run and the app's root closure remains open.

### Boundary map

The work crosses distinct contracts. A seam closes only when both sides of its
boundary agree on the contract and a consumer executes across it:

| Boundary | Producer → consumer | Current failure class | Required evidence |
|---|---|---|---|
| Compiler bootstrap | Zig build/bootstrap → Jac compiler sources and CLI | The normal build creates and runs a JacPython/CPython payload; frozen Jac compilation also re-enters the active pass module through `pipeline.jac`. | Build and invoke `jac` with no Python executable, payload, or Python-linked library. |
| Compiler module ABI | Jac module exports and layouts → imported Jac declarations/calls | Missing public exports surface as runtime `cannot import name`; imported native calls and cross-module aggregate layouts have compiler/runtime gaps. | Compiler-derived import edges resolve names, signatures, and layouts; native consumer probes link and execute. |
| Prepare and placement | Project roots and requested placement → resolved graph and lowered units | Stale seals, test-annex folding, and implicit demotions obscure the actual execution codespace. | Revision-bound manifests for each product and test root record import edges, annexes, actual placement, and demotion cause. |
| Native operation/runtime ABI | Jac standard-library call → Zig/platform implementation → OS | Process, terminal, network, filesystem, threading, Unicode, and URL/IP semantics are incomplete or platform-uneven. | Minimal native consumers exercise success, failure, timeout/cancellation, and cleanup on macOS and Linux. |
| App object graph | Agent/UI/TUI type and callback producer → imported consumer | UI records, walkers/events, callbacks, and shell/session objects cross compilation units; current explicit server pins conceal unresolved native boundaries. | Root execution constructs, mutates, dispatches, renders, and disposes the same native objects without Python/server crossings. |
| Test boundary | Test root/annex and fixture → native test runner | `jac test` dispatches in server codespace; same-stem annexes affect product units; Node fixture processes remain an intermediate dependency. | Each test is an isolated native root; fixture lifecycle and reporting execute natively with Python and Node absent. |
| Release boundary | Source and build graph → shipped executable and workflow | Python source/runtime payload and build/release assumptions remain in the vendored compiler. | Clean macOS/Linux build, run, and test; source, dependency, loaded-library, and artifact scans satisfy the no-Python inventory. |

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
