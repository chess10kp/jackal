#!/usr/bin/env bash
# Memory budget gate for the Jackal harness.
#
# Runs the target under scripted stdin (one mock turn, quiet idle window),
# samples RSS across the whole process tree, and reports:
#
#   resident  peak tree total during the idle window (the number that must
#             fit the 100 MB budget)
#   peak      highest instantaneous tree total anywhere in the run
#             (boot/compile pipeline — tracked separately, not budgeted)
#
# Usage: scripts/mem-profile.sh [--budget-resident MB] [--budget-peak MB] [cmd...]
# Default cmd: <jac> run main.jac --mode yolo (from app/).
# For a sealed bundle: scripts/mem-profile.sh ../jac run dist/jackal.jab --mode yolo
# Requires JACKAL_MODEL unset->mock, JAC or <repo>/jac present.
set -u
cd "$(dirname "$0")/.."
REPO="$PWD"

JAC="${JAC:-$REPO/jac}"
[ -x "$JAC" ] || { echo "mem-profile: no jac at $JAC" >&2; exit 2; }
export JACKAL_ROOT="${JACKAL_ROOT:-$REPO}"
export JACKAL_AGENT_DIR="${JACKAL_AGENT_DIR:-$REPO/pi}"
export JACKAL_MODEL="${JACKAL_MODEL:-mock}"

BUDGET_RESIDENT=""
BUDGET_PEAK=""
IDLE=8
CMD=()
while [ $# -gt 0 ]; do
  case "$1" in
    --budget-resident) shift; BUDGET_RESIDENT="$1" ;;
    --budget-peak) shift; BUDGET_PEAK="$1" ;;
    --idle) shift; IDLE="$1" ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) CMD+=("$1") ;;
  esac
  shift
done
[ ${#CMD[@]} -gt 0 ] || CMD=("$JAC" "run" "main.jac" "--mode" "yolo")

cd "$REPO/app"
OUT="$(node "$REPO/scripts/mem_profile.mjs" --idle-seconds "$IDLE" \
        -- "${CMD[@]}")" || { echo "mem-profile: sampler failed" >&2; exit 2; }
cd "$REPO"

node --input-type=module - "$OUT" "${BUDGET_RESIDENT:-}" "${BUDGET_PEAK:-}" <<'JS'
const result = JSON.parse(process.argv[2]);
const resident = result.idle_kb / 1024;
const peak = result.tree_peak_kb / 1024;
const worst = result.worst_process ?? {};
console.log(`resident (idle tree total): ${resident.toFixed(0)} MB`);
console.log(`peak     (whole run):       ${peak.toFixed(0)} MB`);
if (worst.pid !== undefined) {
  console.log(`worst process: ${worst.exe} ${(worst.kb / 1024).toFixed(0)} MB (pid ${worst.pid})`);
}
let failed = false;
for (const [index, label, measured] of [[3, 'resident', resident], [4, 'peak', peak]]) {
  const raw = process.argv[index];
  if (raw) {
    const budget = Number(raw);
    console.log(`${label} budget: ${budget.toFixed(0)} MB`);
    if (measured > budget) failed = true;
  }
}
process.exitCode = failed ? 1 : 0;
JS
RC=$?
[ $RC -ne 0 ] && echo "mem-profile: BUDGET EXCEEDED"
exit $RC
