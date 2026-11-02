#!/usr/bin/env bash
# Provision the macOS lane: install the workspace compiler `./jac`.
#
# Two lanes, because the published binary and the workspace build differ in
# exactly one respect that matters here:
#
#   --download (default)  Fetch the self-contained release binary
#                         (jac-<ver>-macos-aarch64, bundled runtime, no Python
#                         or pip needed) and install it as ./jac. No compiler
#                         build, no Xcode, no Zig. ~114 MB.
#
#   --build               Clone/build vendor/jac with scripts/setup-vendor-jac.sh.
#                         Needs Xcode CLT + Zig 0.16.0, and pulls the pinned
#                         LLVM slice (~3.4 GB). Only needed to work on native
#                         lowering / probe the app seal against current main --
#                         running Jackal does not need it.
#
# Run it from anywhere; it installs into the repository root.
#
# On the fast path: `run.sh` launches with `jac run -b python`, which is an
# upstream flag and works with the released binary. The additional
# JAC_IGNORE_PLACEMENT_PINS hook that run.sh also exports is local to the
# vendor checkout (not on upstream main, absent from the v0.38.3 release), so
# on a downloaded binary it is simply inert -- harmless, not required.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="jaseci-labs/jac"
DEFAULT_VERSION="0.38.3"
VERSION="${JAC_VERSION:-$DEFAULT_VERSION}"
LANE="download"
INSTALL_DEPS=1

usage() {
  cat <<EOF
Usage: scripts/setup-macos.sh [options]

Installs the workspace compiler at $REPO_ROOT/jac.

Options:
  --download          Install the published release binary (default).
  --build             Build vendor/jac instead (Zig 0.16.0 + Xcode CLT;
                      for native-lowering work, not for running jackal).
  --version V         Release version for --download (default $DEFAULT_VERSION,
                      or \$JAC_VERSION).
  --skip-deps         Do not run 'jac install' in app/ afterwards.
  -h, --help          This message.

After it succeeds:
  ./run.sh                     # TUI
  cd app && ../jac build       # seal check (does not use the dev fast path)
EOF
}

info() { printf '\033[0;34m[setup-macos]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[setup-macos]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[0;31m[setup-macos]\033[0m %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --download) LANE="download" ;;
    --build) LANE="build" ;;
    --version)
      [[ $# -ge 2 ]] || die "--version needs a value"
      VERSION="$2"
      shift
      ;;
    --skip-deps) INSTALL_DEPS=0 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

# --- Platform gates -------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] ||
  die "this script provisions macOS. On Linux use ./scripts/setup-vendor-jac.sh."
[[ "$(uname -m)" == "arm64" ]] ||
  die "Apple Silicon (arm64) only: the release ships no macos-x86_64 asset (upstream #8805) and the native path is untested there. Build from source on Intel at your own risk."

[[ -n "${REPO_ROOT:-}" && -d "$REPO_ROOT/app" ]] || die "cannot find app/ -- is this the jackal checkout?"

# --- Compiler lane --------------------------------------------------------
install_from_release() {
  local asset="jac-${VERSION}-macos-aarch64"
  local base="https://github.com/${REPO}/releases/download/v${VERSION}"
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  info "downloading ${asset} (v${VERSION})"
  curl -fsSL --retry 3 -o "$tmp/$asset" "$base/$asset" ||
    die "download failed: $base/$asset (does v${VERSION} exist? see https://github.com/${REPO}/releases)"
  curl -fsSL --retry 3 -o "$tmp/$asset.sha256" "$base/$asset.sha256" ||
    die "checksum download failed: $base/$asset.sha256"

  (cd "$tmp" && shasum -a 256 -c "$asset.sha256" >/dev/null) ||
    die "checksum mismatch for $asset -- refusing to install"

  install -m 0755 "$tmp/$asset" "$REPO_ROOT/jac"
  info "installed $REPO_ROOT/jac ($asset)"
}

build_from_source() {
  command -v xcode-select >/dev/null && xcode-select -p >/dev/null 2>&1 ||
    die "--build needs Xcode Command Line Tools: xcode-select --install"
  command -v zig >/dev/null ||
    die "--build needs Zig 0.16.0 on PATH (https://ziglang.org/download/)"
  [[ "$(zig version)" == "0.16.0" ]] ||
    die "--build needs Zig 0.16.0 exactly (found $(zig version))"

  info "building vendor/jac (first run pulls the LLVM slice, ~3.4 GB)"
  "$REPO_ROOT/scripts/setup-vendor-jac.sh"
}

if [[ "$LANE" == "build" ]]; then
  build_from_source
else
  install_from_release
fi

# --- Verify ---------------------------------------------------------------
[[ -x "$REPO_ROOT/jac" ]] || die "$REPO_ROOT/jac is missing or not executable"
JAC_VERSION_OUT="$("$REPO_ROOT/jac" --version 2>&1 | tail -1)" ||
  die "$REPO_ROOT/jac --version failed (wrong arch, or quarantined: xattr -d com.apple.quarantine ./jac)"
info "compiler: $JAC_VERSION_OUT"

# --- Project dependencies -------------------------------------------------
# app/jac.toml declares httpx and pyte under [dependencies.pypi]; the bundled
# runtime starts empty, so the TUI will not import until they are installed.
if [[ "$INSTALL_DEPS" == "1" ]]; then
  info "installing project dependencies (app/jac.toml -> [dependencies.pypi])"
  (cd "$REPO_ROOT/app" && "$REPO_ROOT/jac" install) ||
    die "'jac install' failed -- rerun it by hand from app/, or pass --skip-deps to skip"
fi

# --- Report ---------------------------------------------------------------
cat <<EOF

Ready.

  compiler : $REPO_ROOT/jac  ($JAC_VERSION_OUT)
  lane     : $LANE
  run      : ./run.sh            (TUI)
  seal     : cd app && ../jac build

EOF

if [[ "$LANE" == "download" ]]; then
  cat <<EOF
Note: run.sh launches with 'jac run -b python' (upstream flag, works with this
binary), so the dev fast path is intact. The extra JAC_IGNORE_PLACEMENT_PINS
hook is local to the vendor checkout and is inert here -- it costs nothing.

EOF
fi
