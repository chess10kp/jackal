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
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auth/skills/chains catalogs live in the repo, not in app/.
export JACKAL_ROOT="$REPO_ROOT"
export JACKAL_AGENT_DIR="${JACKAL_AGENT_DIR:-$REPO_ROOT/pi}"
unset JAC_HANDOFF

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

case "${JACKAL_ENTRY:-tui}" in
  tui)  src="tui/shell.jac"; out="jackal-tui" ;;
  main) src="main.jac";      out="jackal" ;;
  *) echo "JACKAL_ENTRY must be tui or main" >&2; exit 2 ;;
esac

cd "$REPO_ROOT/app"
mkdir -p .jac/bin
"$NEOJAC" build "$src" -o ".jac/bin/$out" ${JACKAL_RELEASE:+--release}
exec ".jac/bin/$out" "$@"
