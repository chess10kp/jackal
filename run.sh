#!/usr/bin/env bash
# Launch the Jackal TUI.
#
# Deliberately one process: `jac run tui/shell.jac` from app/ directly. The
# old path went through app/run.jac, which re-spawned whatever `jac` happened
# to be on PATH -- often a different build than the workspace ./jac, and one
# extra full compile on every launch.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -x "$REPO_ROOT/jac" ]]; then
  echo "workspace Jac binary missing; run ./scripts/setup-vendor-jac.sh with Zig 0.16.0" >&2
  exit 127
fi

# Auth/skills/chains catalogs live in the repo, not in app/.
export JACKAL_ROOT="$REPO_ROOT"
export JACKAL_AGENT_DIR="${JACKAL_AGENT_DIR:-$REPO_ROOT/pi}"

# JAC_HANDOFF names an enclosing jac process's CLI endpoint; inheriting it
# deadlocks the child `jac`.
unset JAC_HANDOFF
unset JAC_IGNORE_PLACEMENT_PINS

cd "$REPO_ROOT/app"
exec "$REPO_ROOT/jac" run tui/shell.jac "$@"
