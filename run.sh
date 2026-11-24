#!/usr/bin/env bash
# Launch the Jackal TUI as a native executable built by neojac.
#
# `neojac build` compiles app/tui/shell.jac (and everything it imports) into
# one self-contained binary. Reuse it until a build is explicitly requested.
#
#   ./run.sh               run the TUI (build only if binary missing)
#   JACKAL_ENTRY=main ./run.sh [--json|...]   the line REPL / JSONL frontend
#   JACKAL_FORCE_BUILD=1 ./run.sh            rebuild before run
#   JACKAL_RELEASE=0 JACKAL_FORCE_BUILD=1 ./run.sh   build without release optimizations
#
# Pre-built binaries live in app/.jac/bin/ — run them directly:
#   ./bin/jackal-tui    ./bin/jackal
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
if [[ "$script_path" == */* ]]; then
  CDPATH= cd -- "${script_path%/*}/"
fi
REPO_ROOT="$PWD"

# Auth/skills/chains catalogs live in the repo, not in app/.
export JACKAL_ROOT="$REPO_ROOT"
export JACKAL_AGENT_DIR="${JACKAL_AGENT_DIR:-$REPO_ROOT/pi}"
unset JAC_HANDOFF

case "${JACKAL_ENTRY:-tui}" in
  tui)  src="tui/shell.jac"; out="jackal-tui" ;;
  main) src="main.jac";      out="jackal" ;;
  *) echo "JACKAL_ENTRY must be tui or main" >&2; exit 2 ;;
esac

cd "$REPO_ROOT/app"
bin=".jac/bin/$out"
if [[ "${JACKAL_FORCE_BUILD:-0}" == "1" ]] || [[ ! -x "$bin" ]]; then
  if [[ -z "${NEOJAC:-}" ]]; then
    NEOJAC="$(command -v neojac 2>/dev/null || true)"
    if [[ -z "$NEOJAC" && -x "${HOME}/.local/bin/neojac" ]]; then
      NEOJAC="${HOME}/.local/bin/neojac"
    fi
  fi
  if [[ -z "$NEOJAC" ]]; then
    echo "neojac not found; install: curl -fsSL https://github.com/jaseci-labs/neojac-releases/releases/latest/download/install.sh | bash" >&2
    exit 127
  fi
  mkdir -p .jac/bin
  build_flags=()
  if [[ "${JACKAL_RELEASE:-1}" != "0" ]]; then
    build_flags+=(--release)
  fi
  "$NEOJAC" build "$src" -o "$bin" "${build_flags[@]}"
fi
exec "$bin" "$@"
