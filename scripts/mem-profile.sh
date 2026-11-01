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
OUT="$(python3 "$REPO/scripts/mem_profile.py" --idle-seconds "$IDLE" \
        -- "${CMD[@]}")" || { echo "mem-profile: sampler failed" >&2; exit 2; }
cd "$REPO"

python3 - "$OUT" ${BUDGET_RESIDENT:+$BUDGET_RESIDENT} ${BUDGET_PEAK:+$BUDGET_PEAK} <<'PY'
import json, sys
r = json.loads(sys.argv[1])
res = r["idle_kb"] / 1024.0
peak = r["tree_peak_kb"] / 1024.0
worst = r.get("worst_process") or {}
print(f"resident (idle tree total): {res:.0f} MB")
print(f"peak     (whole run):       {peak:.0f} MB")
if worst:
    print(f"worst process: {worst.get('exe')} {worst.get('kb', 0)/1024:.0f} MB "
          f"(pid {worst.get('pid')})")
fail = False
if len(sys.argv) > 2:
    budget = float(sys.argv[2])
    print(f"resident budget: {budget:.0f} MB")
    if res > budget:
        fail = True
if len(sys.argv) > 3:
    budget = float(sys.argv[3])
    print(f"peak budget: {budget:.0f} MB")
    if peak > budget:
        fail = True
sys.exit(1 if fail else 0)
PY
RC=$?
[ $RC -ne 0 ] && echo "mem-profile: BUDGET EXCEEDED"
exit $RC
