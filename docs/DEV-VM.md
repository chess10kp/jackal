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

Both Linux x86_64 release executables were built with 0.3.2:

- `/data/home/repos/jackal/app/.jac/bin/jackal-tui`
- `/data/home/repos/jackal/app/.jac/bin/jackal`

Use the existing binaries through `./run.sh` or `./bin/jackal[-tui]`.

## Build compatibility handoff

The development environment is provisioned, but rebuilding with the default
0.5.3 compiler remains blocked by the existing manifest migration: E2231 requires
`archwire.jac`, E3058 rejects the old lint selection, and E3059 rejects its ignore
configuration. Owner: Jackal's toolchain integration. Migrate project wiring and
lint configuration while preserving the native placement policy.

Version 0.3.2 successfully builds each frontend from the original source, but
also rewrites project sources and generates implementation/archwire files. A
second build then fails with E1141/E2097 on generated `plugin_host` wires. The
setup builds used a clean source copy for each entry, and restored the original
working tree afterwards. Do not run this compiler on the only copy of pending
work. Owner: Jackal/neojac integration; validate a supported compiler and project
configuration with repeatable builds that preserve pending work. No placement
pins or application sources were changed for this setup.

The separate vendored `./jac` compiler and Zig are not installed. The placement
seal and the full 78-module suite have therefore not been verified on this VM;
use the repository's CI for the full suite as directed by `docs/TESTING.md`.
