#!/usr/bin/env bash
# Re-run js2jac floor conversion for pi-tui reference sources.
set -euo pipefail

JAC_REPO="${JAC_LLM_JAC:-/home/jac/repos/jac_llm_data/jaseci/jac}"
PI_TUI="${PI_TUI_SRC:-/home/jac/repos/notes/reference/pi/packages/tui}"
JACKAL_TUI="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$JACKAL_TUI/pi_jac_floor"
DRIVER="$JACKAL_TUI/scripts/holeconvert.mjs"
[[ -f "$DRIVER" ]] || DRIVER="$JAC_REPO/../scripts/js2jac_dataset/source/holeconvert.mjs"
[[ -f "$DRIVER" ]] || DRIVER="/home/jac/repos/jac_llm_data/scripts/js2jac_dataset/source/holeconvert.mjs"
FLOOR_TOOL="$JACKAL_TUI/scripts/js2jac_floor.mjs"
[[ -f "$FLOOR_TOOL" ]] || { echo "missing floor converter: $FLOOR_TOOL"; exit 1; }

export PATH="$HOME/.local/bin:$PATH"
command -v jac >/dev/null || { echo "jac not on PATH"; exit 1; }
command -v bun >/dev/null || { echo "bun required for holeconvert.mjs"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
node "$FLOOR_TOOL" \
  --source-root "$PI_TUI/src" \
  --base "$PI_TUI" \
  --out "$OUT" \
  --driver "$DRIVER" \
  --summary "$JACKAL_TUI/pi_jac_floor_summary.json" \
  --project-log "$JACKAL_TUI/pi_jac_floor_project_check.txt" \
  --jac-cwd "$JAC_REPO" \
  --project-timeout 180

echo "Wrote $OUT"
