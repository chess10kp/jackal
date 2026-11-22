#!/usr/bin/env bash
# Launch the Jackal TUI as a native executable built by neojac.
#
# `neojac build` compiles app/tui/shell.jac (and everything it imports) into
# one self-contained binary — no CPython, no JIT at launch. neojac's build
# cache makes a rebuild of unchanged sources near-instant, so this builds on
# every launch and then execs the binary.
#
#   ./run.sh               build + run the TUI
#   JACKAL_ENTRY=main ./run.sh [--json|...]   the line REPL / JSONL frontend
#   JACKAL_LEGACY_JAC=1 ./run.sh             old path: workspace ./jac run (Python codespace)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auth/skills/chains catalogs live in the repo, not in app/.
export JACKAL_ROOT="$REPO_ROOT"
export JACKAL_AGENT_DIR="${JACKAL_AGENT_DIR:-$REPO_ROOT/pi}"
unset JAC_HANDOFF

if [[ "${JACKAL_LEGACY_JAC:-0}" == "1" ]]; then
  if [[ ! -x "$REPO_ROOT/jac" ]]; then
    echo "workspace Jac binary missing; run ./scripts/setup-vendor-jac.sh with Zig 0.16.0" >&2
    exit 127
  fi
  export JAC_IGNORE_PLACEMENT_PINS=1
  cd "$REPO_ROOT/app"
  exec "$REPO_ROOT/jac" run -b python tui/shell.jac "$@"
fi

NEOJAC="${NEOJAC:-$(command -v neojac || true)}"
if [[ -z "$NEOJAC" ]]; then
  echo "neojac not found; install: curl -fsSL https://github.com/jaseci-labs/neojac-releases/releases/latest/download/install.sh | bash" >&2
  exit 127
fi

case "${JACKAL_ENTRY:-tui}" in
  tui)  src="tui/shell.jac"; out="jackal-tui" ;;
  main) src="main.jac";      out="jackal" ;;
  *) echo "JACKAL_ENTRY must be tui or main" >&2; exit 2 ;;
esac

cd "$REPO_ROOT/app"
mkdir -p .jac/bin
"$NEOJAC" build "$src" -o ".jac/bin/$out" ${JACKAL_RELEASE:+--release}
exec ".jac/bin/$out" "$@"
