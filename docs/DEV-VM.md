# Jackal development VM

Default VM: `jackal-extra-1`, owned by `nitin@jaseci.org`.
Checkout: `/data/home/repos/jackal` (`~/repos/jackal`).

```bash
instabox ssh jackal-extra-1
cd ~/repos/jackal
./run.sh
# Headless:
JACKAL_MODEL=mock ./bin/jackal -p "hello"
```

The checkout includes local uncommitted work and Git history. Claude and Codex
conversation history was copied with the user's approval. The original checkout
remains separate; changes do not synchronize automatically. GitHub credentials
have not been configured on the VM; set them up there before push/pull.

## Native tools and binaries

Node 22 and OpenSSL development headers are available. Neojac 0.5.3 is installed
at `/data/workspace/neojac`, linked from `~/.local/bin/neojac`. The checksum-verified
0.3.2 release is installed separately under `~/.local/lib/neojac-0.3.2`, linked
from `~/.local/bin/neojac-0.3.2`.

Both Linux x86_64 release executables are built with **neojac 0.5.3** (rebuilt
and verified 2026-11-27):

- `/data/home/repos/jackal/app/.jac/bin/jackal-tui`
- `/data/home/repos/jackal/app/.jac/bin/jackal`

Use them through `./run.sh` or `./bin/jackal[-tui]`. Do **not** build this tree
with the separately installed 0.3.2: it rewrites project sources and generates
`implementation`/`archwire` files, and a second build then fails with
E1141/E2097 on the generated `plugin_host` wires.

## Build and test status (neojac 0.5.3, verified 2026-11-27)

The 0.5 project migration landed (`app/archwire.jac`, `app/impl/` annexes, commit
`297d276`); the old E2231/E3058/E3059 handoff is closed. Rebuilds are green and
repeatable:

```bash
cd app
neojac build tui/shell.jac -o .jac/bin/jackal-tui --release   # ~11 s on a change
neojac build main.jac      -o .jac/bin/jackal     --release
JACKAL_MODEL=mock ../bin/jackal -p "hello"                     # smoke: prints "mock: hello"
```

Builds are content-hash cached: an unchanged tree rebuilds in under 0.1 s and
leaves the existing binary in place, so touch a source file when you need real
compiler output to read.

Tests run per module with `neojac test <module.jac>` (from `app/`); 80 test
modules take about 4 minutes at `-P4`. Two rules for this box (4 vCPU / 8 GiB):

- **Run `e2e/*` serially.** Those suites shell out to `neojac build`; when other
  suites hold memory at the same time clang dies
  (`clang integrated assembler command failed with exit code 135`) and the suite
  reports the useless `e2e: neojac build main.jac failed`. They pass 3/10/14
  tests one at a time.
- Cap each process (see `scripts/neojac-test-each.sh`, `systemd-run -p MemoryMax=4G`)
  when running anything in parallel.

Status on 2026-11-27: 79 of 80 modules green. The only red module is the
quarantined `tui/harness` (7 passed, 2 failed — the known mode-badge `YOLO`/`AUTO`
assertions listed in `scripts/test-quarantine.txt`). Fixed during this run:
`ui/input` "readline control and meta keys decode" — `decode_sequence` never
mapped `\x02`/`\x06`, so `ctrl+b`/`ctrl+f` arrived as `TextEvent` even though
`app/tui/impl/input.impl.jac` already handles those key names.

The separate vendored `./jac` compiler and Zig are not installed, so `scripts/test.sh`
(which drives `jac test`) still cannot run here, and the `jac build` placement
seal is unverified on this VM — CI remains the authority for both
(`docs/TESTING.md`).

Note: `docs/` is gitignored, so commit a doc change here with `git add -f`.
