#!/usr/bin/env bash
# Re-run js2jac floor conversion for pi-agent-core (+ optional sibling packages).
# Mirrors tui/scripts/js2jac_pi_tui.sh — emit floor under app/pi_agent_floor/.
set -euo pipefail

PI_ROOT="${PI_AGENT_SRC:-/home/jac/repos/notes/reference/pi/packages}"
PACKAGES="${PI_PACKAGES:-agent}"
JACKAL="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${PI_AGENT_OUT:-$JACKAL/app/pi_agent_floor}"
DRIVER="$JACKAL/tui/scripts/holeconvert.mjs"
FLOOR_TOOL="$JACKAL/tui/scripts/js2jac_floor.mjs"
[[ -f "$DRIVER" ]] || { echo "missing holeconvert: $DRIVER"; exit 1; }
[[ -f "$FLOOR_TOOL" ]] || { echo "missing floor converter: $FLOOR_TOOL"; exit 1; }

export PATH="$HOME/.local/bin:$PATH"
command -v jac >/dev/null || { echo "jac not on PATH"; exit 1; }
command -v bun >/dev/null || { echo "bun required for holeconvert.mjs"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
node "$FLOOR_TOOL" \
  --package-root "$PI_ROOT" \
  --packages "$PACKAGES" \
  --out "$OUT" \
  --driver "$DRIVER" \
  --summary "$JACKAL/app/pi_agent_floor_summary.json" \
  --project-log "$JACKAL/app/pi_agent_floor_project_check.txt" \
  --jac-cwd "$JACKAL"

echo "Wrote $OUT"
echo "Summary: $JACKAL/app/pi_agent_floor_summary.json"
