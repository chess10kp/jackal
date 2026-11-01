#!/usr/bin/env bash
# Memory budget gate for the Jackal harness (Linux only; uses /proc).
#
# Runs the interactive harness under the mock provider with a short scripted
# session, samples RSS across the whole process tree, and reports peak
# per-process and instantaneous tree totals split at the boot banner:
#
#   boot   — everything before the banner (prep/compile/seal pipeline)
#   post   — the resident runtime (what must fit the 100 MB budget)
#
# Usage: scripts/mem-profile.sh [--budget-resident MB] [--budget-boot MB] [cmd...]
# Exit 1 if a budget is exceeded (script exits nonzero on missing tooling).
set -u
cd "$(dirname "$0")/.."
REPO="$PWD"

JAC="${JAC:-$REPO/jac}"
[ -x "$JAC" ] || { echo "mem-profile: no jac at $JAC" >&2; exit 2; }
export JACKAL_ROOT="${JACKAL_ROOT:-$REPO}"
export JACKAL_AGENT_DIR="${JACKAL_AGENT_DIR:-$REPO/pi}"
export JACKAL_MODEL="${JACKAL_MODEL:-mock}"

BUDGET_RESIDENT=""
BUDGET_BOOT=""
CMD=()
while [ $# -gt 0 ]; do
  case "$1" in
    --budget-resident) shift; BUDGET_RESIDENT="$1" ;;
    --budget-boot) shift; BUDGET_BOOT="$1" ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) CMD+=("$1") ;;
  esac
  shift
done
[ ${#CMD[@]} -gt 0 ] || CMD=("$JAC" "run" "main.jac" "--mode" "yolo")

cd "$REPO/app"
OUT="$(python3 "$REPO/scripts/mem_profile.py" --marker "all-Jac agent harness" \
        -- "${CMD[@]}")" || { echo "mem-profile: sampler failed" >&2; exit 2; }
cd "$REPO"

python3 - "$OUT" ${BUDGET_RESIDENT:+$BUDGET_RESIDENT} ${BUDGET_BOOT:+$BUDGET_BOOT} <<'PY'
import json, sys
r = json.loads(sys.argv[1])
res = r["post_boot_peak_total_kb"] / 1024.0
boot = r["boot_peak_total_kb"] / 1024.0
worst = r.get("worst_process") or {}
print(f"resident (post-boot tree peak): {res:.0f} MB")
print(f"boot     (prep pipeline peak): {boot:.0f} MB")
if worst:
    print(f"worst process: {worst.get('exe')} {worst.get('kb', 0)//1024} MB "
          f"(pid {worst.get('pid')})")
fail = False
if len(sys.argv) > 2:
    budget = float(sys.argv[2])
    print(f"resident budget: {budget:.0f} MB")
    if res > budget:
        fail = True
if len(sys.argv) > 3:
    budget = float(sys.argv[3])
    print(f"boot budget: {budget:.0f} MB")
    if boot > budget:
        fail = True
sys.exit(1 if fail else 0)
PY
RC=$?
[ $RC -ne 0 ] && echo "mem-profile: BUDGET EXCEEDED"
exit $RC
