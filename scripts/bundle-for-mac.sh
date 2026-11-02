#!/usr/bin/env bash
# Package this Linux workspace so it can be resumed on an Apple Silicon Mac.
#
# What travels and why:
#   jackal.bundle            git bundle of HEAD on the current branch. Clone-able
#                            without a remote: `git clone jackal.bundle jackal`.
#   vendor-jac-src.tar.gz    vendor/jac source tree (no .git, no caches, ~20 MB).
#                            The subtrees that matter for a `--build` lane are
#                            exactly what this checkout has, including the local
#                            compiler commits. vendor/jac is gitignored here and
#                            its caches are multi-GB, so shipping the source is
#                            cheaper and more faithful than re-deriving it.
#   vendor-jac/*.patch       The divergence as mbox files, for provenance and
#                            for applying to a fresh upstream clone instead.
#   pi/auth.json             Provider credentials (real file, not the symlink).
#                            Written 0600; .gitignore covers the repo copy.
#   README-MACOS.md          Exact commands to run on the Mac.
#
# NOT included (rebuild or re-download on the Mac):
#   ./jac                    platform binary: ELF x86_64 here, Mach-O arm64 there.
#   .llvm-build/             pinned LLVM slice (~3.4 GB), re-fetched by zig build.
#   zig-out/ .zig-cache/ zig-pkg/ .pbs-build/ .payload-layers/ .python-build/
#   .precompiled-build/ *.so build products; none of it is portable.
#   The compiler kernel (libjac_compiler.so): target-specific, and stale here
#   (built 2026-10-31, before the 2026-11-01 hasattr fixes).
#
# Usage: scripts/bundle-for-mac.sh [--out DIR] [--with-sessions]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_ROOT/dist"
WITH_SESSIONS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --with-sessions) WITH_SESSIONS=1; shift ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

info() { printf '\033[0;34m[bundle]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[bundle]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[0;31m[bundle]\033[0m %s\n' "$*" >&2; exit 1; }

BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
[[ -n "$BRANCH" ]] || die "detached HEAD: check out a branch first"

PACK="$OUT/jackal-to-mac"
rm -rf "$PACK"
mkdir -p "$PACK/vendor-jac"

info "bundling jackal @ $BRANCH"
git -C "$REPO_ROOT" bundle create "$PACK/jackal.bundle" HEAD

VENDOR="$REPO_ROOT/vendor/jac"
BASE=""
if [[ -d "$VENDOR" ]]; then
  # The base is the merge-base, not origin/main: upstream main has moved on
  # since this checkout forked (2026-10-25), and diffing against the newer tip
  # would silently import a week of unrelated compiler changes.
  BASE="$(git -C "$VENDOR" merge-base HEAD origin/main 2>/dev/null || true)"
  [[ -n "$BASE" ]] || BASE="$(head -1 "$VENDOR/.git/shallow" 2>/dev/null || true)"

  info "exporting vendor/jac divergence against ${BASE:0:9}"
  git -C "$VENDOR" format-patch --quiet --no-numbered --suffix=.patch \
    --output-directory "$PACK/vendor-jac" "$BASE..HEAD" \
    || die "could not export vendor patches"
  printf 'base %s\n' "$BASE" > "$PACK/vendor-jac/base.txt"
  git -C "$VENDOR" log --oneline -1 HEAD >> "$PACK/vendor-jac/base.txt"

  info "packing vendor/jac source (no .git, no caches)"
  tar -C "$VENDOR" -czf "$PACK/vendor-jac-src.tar.gz" \
    --exclude=.git --exclude=.llvm-build --exclude=zig-out --exclude=.zig-cache \
    --exclude=zig-pkg --exclude=.python-build --exclude=.payload-layers \
    --exclude=.pbs-build --exclude=.bun-build --exclude=.precompiled-build \
    --exclude=.jac --exclude=vendor/typeshed/stdlib --exclude='*.artifact.json' \
    --exclude='*.layout.json' --exclude='libjac_compiler.so.lock' \
    --exclude='*.so' --exclude='_bun/bun' --exclude=__pycache__ --exclude='*.pyc' \
    .
else
  warn "no vendor/jac checkout; skipping compiler source and patches"
fi

info "copying provider credentials"
AUTH="$REPO_ROOT/pi/auth.json"
[[ -e "$AUTH" ]] || AUTH="$HOME/.pi/agent/auth.json"
if [[ -f "$AUTH" ]]; then
  install -m 0600 "$AUTH" "$PACK/pi-auth.json"
else
  warn "no auth.json found; write it by hand on the Mac"
fi

if [[ "$WITH_SESSIONS" == 1 && -d "$REPO_ROOT/pi/sessions" ]]; then
  info "copying pi/sessions"
  cp -R "$REPO_ROOT/pi/sessions" "$PACK/pi-sessions"
fi

cat > "$PACK/README-MACOS.md" <<EOF
# Jackal → Apple Silicon Mac

Generated $(date -u +%Y-%m-%dT%H:%MZ) from branch \`$BRANCH\`.
Compiler divergence: \`vendor/jac\` at \`${BASE:-unknown}\` plus the patches in
\`vendor-jac/\` (upstream main has since moved; do not rebase casually).

## 1. Repo

\`\`\`bash
git clone jackal.bundle jackal
cd jackal
git switch -c $BRANCH      # a bundle clone lands detached
\`\`\`

From GitHub instead (branch must be pushed):

\`\`\`bash
git clone git@github.com:chess10kp/jackal && cd jackal && git switch $BRANCH
\`\`\`

## 2. Compiler — running Jackal needs only the published binary

\`\`\`bash
./scripts/setup-macos.sh    # jac-<ver>-macos-aarch64 -> ./jac, then jac install in app/
./run.sh                    # TUI
cd app && ../jac build      # seal check, report only
\`\`\`

\`JAC_IGNORE_PLACEMENT_PINS\` is not in a released binary, so run.sh's dev fast
path is inert there; the \`-b python\` it passes is what keeps startup fast.

## 3. Only for native-lowering work

\`\`\`bash
tar -xzf vendor-jac-src.tar.gz -C vendor/jac    # same tree as the Linux box
./scripts/setup-macos.sh --build                # Xcode CLT + Zig 0.16.0; LLVM slice ~3.4 GB
cd vendor/jac && zig build -Ddev -Dpayload-progress   # build in place, do NOT run setup-vendor-jac.sh
\`\`\`

\`scripts/setup-vendor-jac.sh\` runs \`git fetch origin main && git checkout
--detach origin/main\`, which discards the local divergence. If you do use it,
re-apply \`vendor-jac/*.patch\` afterwards on top of \`${BASE:-the recorded base}\`.

Also note: the compiler kernel cannot be copied from the Linux box (different
triple, different CPython) and the Linux one is stale anyway — a >32 GB host is
needed to rebuild it there.

## 4. Credentials

\`\`\`bash
mkdir -p ~/.pi/agent && install -m 0600 pi-auth.json ~/.pi/agent/auth.json
ln -sfn ~/.pi/agent/auth.json pi/auth.json
export JACKAL_AGENT_DIR="\$PWD/pi" JACKAL_ROOT="\$PWD"
\`\`\`

## 5. Not carried (expected)

\`./jac\`, \`.llvm-build/\`, \`zig-out/\`, \`.zig-cache/\`, \`zig-pkg/\`, \`.pbs-build/\`,
\`.payload-layers/\`, \`.python-build/\`, \`.precompiled-build/\` and any \`*.so\`.
EOF

info "writing archive"
TARBALL="$OUT/jackal-to-mac.tar.gz"
tar -C "$OUT" -czf "$TARBALL" jackal-to-mac
rm -rf "$PACK"
chmod 0600 "$TARBALL"   # it carries pi/auth.json

ls -lh "$TARBALL"
printf '\nNext: scp %s <mac>:~/\n' "$TARBALL"
