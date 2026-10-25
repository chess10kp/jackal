# Local Jac compiler checkout (`vendor/jac`)

**Updated:** 2026-10-25 · **Source:** `jaseci-labs/jac` `main` @ `eafdb1682321f93d60c8590119e1d7e1b6e4fd38` · **Form:** local shallow clone (ignored by git)

## Why a local checkout

Jackal runs against the newest upstream compiler through a workspace-local binary. The source checkout and build products stay ignored; `./jac` is also ignored and is rebuilt with `./scripts/setup-vendor-jac.sh`.

- **Fix now, in-repo**: any native-path fix lands in `vendor/jac/**` and the dev binary picks it up immediately.
- **PR upstream in parallel**: the same change goes to jaseci-labs/jac; when it eventually merges we sync and drop our local copy.
- **No waiting**: divergence is paid down on *our* schedule, not upstream's.

## Layout

```
vendor/jac/                  # upstream repo root (local shallow clone)
├── jac/                     # the compiler package
│   ├── build.zig            # one-command entry (fetch-llvm, fetch-bun, -Ddev, release)
│   ├── jaclang/             # compiler source — edits here run live under -Ddev
│   │   ├── compiler/backends/native/   # graph-shaped native compiler + LLVM IR
│   │   └── runtime/na_stdlib/          # native stdlib floors
│   ├── launcher/            # single-binary launcher internals
│   └── native/              # llvmlite FFI shim (C++, verbatim upstream)
└── scripts/                 # upstream helpers (fresh_env.sh — see gotchas)
```

`vendor/jac` maps the upstream **repo root** 1:1. The build script fetches the latest `main`, builds in `vendor/jac/jac`, then installs the resulting executable at the Jackal root as `./jac`.

## Build

```bash
./scripts/setup-vendor-jac.sh     # wrapper — see gotchas below
export PATH="$PWD/vendor/jac/jac/zig-out/bin:$PATH"
jac --version
```

Requirements: Zig 0.16.0 and network access for upstream source and pinned build dependencies. The `-Ddev` binary **links the local compiler source live**; run the setup script again after updating compiler sources or launcher files.

## Editing rules

1. Fixes must stay **upstream-able**: conventional commits, no co-author lines, no gratuitous divergence from upstream structure.
2. Keep changes confined to the native path we depend on; if a change would conflict with upstream direction, stop and document it here instead.
3. When an upstream PR containing our fix merges, sync (below) and revert our local copy of the fix in the same change.

## Sync from upstream

```bash
# from the Jackal root; setup fetches latest upstream main before rebuilding
./scripts/setup-vendor-jac.sh
```

## Push a fix upstream

```bash
git subtree split --prefix=vendor/jac --branch vendor-jac-upstream
git push git@github.com:chess10kp/jaseci.git vendor-jac-upstream:<pr-branch>
# open PR against jaseci-labs/jac from the fork
```

## Gotchas

- **`git show-toplevel` breaks inside a subtree.** Upstream scripts that resolve the repo root this way (`scripts/fresh_env.sh`, possibly others) resolve to the *jackal* root when run from `vendor/jac`. Use `scripts/setup-vendor-jac.sh` (which runs the same `zig build` steps with explicit paths) instead of editing the vendored script.
- **Upstream `.gitignore` came along** and covers build products inside the subtree (`.llvm-build/`, `zig-out/`, `.payload-layers/`, `_bun/`, `zig-cache/`). Tracked content is ~28 MB; the multi-GB caches are all ignored.
- **`jac precommit --install`** (part of upstream fresh_env) installs git hooks into whatever repo root it finds — that would be jackal. Optional; skip unless wanted: it formats staged `.jac` files and blocks AI co-author lines.
- **Installed `jac` (0.36.1, pip/`~/.local/bin`) is separate.** Shadow it with `export PATH=.../vendor/jac/jac/zig-out/bin:$PATH` when working on native lowering, or CI/probes will test the wrong compiler.
- **Upstream is slow-moving for us**: never base app/ features on unmerged-upstream behavior *without* the vendor fix present — the vendor is the source of truth for what jackal builds against.

## Relationship to the native roadmap

The gap analysis (`~/notes/jackal-native-gap-analysis.md`) lists the concrete upstream work items; they land as:

| Gap | Where it lands |
|---|---|
| `na_stdlib` modules (`re`, `threading`, `subprocess`, `tempfile`, `queue`, terminal FFI floors) | `vendor/jac/jac/jaclang/runtime/na_stdlib/` |
| compiler intercepts (`os.environ`, `os.listdir`, `walk`, ...) | `vendor/jac/jac/jaclang/compiler/backends/native/na_ir_gen/` |
| graph-shaped OSP lowering | `vendor/jac/jac/jaclang/compiler/backends/native/na_ir_gen/osp.*.jac` |
| lowering failures (E1032, E5092) | same backend + native driver |
| new-module congruence tests | `vendor/jac/jac/jaclang/compiler/tests/fixtures/` + `test_prim_equivalence.jac` |
