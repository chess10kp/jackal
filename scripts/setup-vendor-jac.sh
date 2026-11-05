#!/usr/bin/env bash
# Fetch upstream Jac main and build it into the workspace executable `./jac`.
#
# vendor/jac is a local shallow clone of jaseci-labs/jac (main);
# see docs/VENDOR-JAC.md. Upstream's scripts/fresh_env.sh assumes it runs at
# the repository root (`git rev-parse --show-toplevel`), which inside a
# subtree resolves to the jackal root -- so this wrapper runs the same steps
# with explicit paths.
#
# Output: vendor/jac/jac/zig-out/bin/jac
#   -Ddev links the in-tree compiler source into the binary, so edits to
#   vendor/jac/jac/jaclang/** take effect with no rebuild.
#
# One-time downloads on a fresh machine (idempotent afterwards):
#   - pinned LLVM subset (~84 MB -> .llvm-build/)
#   - pinned bun runtime
#   - checksum-pinned CPython source archive used to build JacPython (not a
#     system-Python or python-build-standalone dependency)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_ROOT="$REPO_ROOT/vendor/jac"
VJ="$VENDOR_ROOT/jac"

command -v zig >/dev/null || { echo "error: zig 0.16.0 required but not on PATH" >&2; exit 1; }
[[ "$(zig version)" == 0.16.0 ]] || { echo "error: Jac requires Zig 0.16.0 (found $(zig version))" >&2; exit 1; }

if [[ ! -d "$VJ" ]]; then
  mkdir -p "$REPO_ROOT/vendor"
  git clone --depth 1 https://github.com/jaseci-labs/jac.git "$VENDOR_ROOT"
else
  if [[ -n "$(git -C "$VENDOR_ROOT" status --porcelain --untracked-files=no)" ]]; then
    echo "error: $VENDOR_ROOT has tracked changes; refusing to replace local source" >&2
    exit 1
  fi
  git -C "$VENDOR_ROOT" fetch --depth 1 origin main
  git -C "$VENDOR_ROOT" checkout --detach origin/main
fi

cd "$VJ"
zig build fetch-llvm
zig build fetch-bun
zig build -Ddev -Dpayload-progress

echo
echo "Built: $VJ/zig-out/bin/jac"
install -m 0755 "$VJ/zig-out/bin/jac" "$REPO_ROOT/jac"
echo "Installed workspace compiler: $REPO_ROOT/jac"
"$REPO_ROOT/jac" --version
