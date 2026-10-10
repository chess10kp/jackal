#!/bin/bash
# Jackal test runner — per-suite isolation for `jac test`.
#
# Runs each app/**/*.test.jac as its own `jac test` process with a wall-clock
# timeout, captures per-suite logs, and prints an aggregate summary.
#
# Usage:
#   scripts/test.sh                       # all suites, sequential
#   scripts/test.sh ui/ agent/            # subsets (path substrings)
#   scripts/test.sh -j4                   # parallel jobs
#   scripts/test.sh --fail-fast           # stop on first failing suite
#   scripts/test.sh -k edit               # keyword filter on suite names
#   scripts/test.sh --exclude app/ui/     # skip suites matching a path substring
#   scripts/test.sh --quarantine scripts/test-quarantine.txt
#                                         # known failures: XFAIL (non-fatal);
#                                         # quarantined passes report XPASS
#
# Env:
#   JAC           jac binary            (default: `jac` on PATH)
#   JACKAL_ROOT   repo root for catalogs (default: repo root)
#   JACKAL_AGENT_DIR bundle dir          (default: <repo>/pi)
#   TIMEOUT       per-suite seconds     (default: 600)
set -u
cd "$(dirname "$0")/.."
REPO="$PWD"

JAC="${JAC:-jac}"
TIMEOUT="${TIMEOUT:-600}"
JOBS=1
FAIL_FAST=0
FILTERS=()
KEYWORDS=()
EXCLUDES=()
QUARANTINE_FILE=""
LOGDIR="$REPO/.testlogs"
mkdir -p "$LOGDIR"

while [ $# -gt 0 ]; do
  case "$1" in
    -j*) JOBS="${1#-j}"; [ -n "$JOBS" ] || { shift; JOBS="$1"; } ;;
    --fail-fast) FAIL_FAST=1 ;;
    --exclude) shift; EXCLUDES+=("$1") ;;
    --quarantine) shift; QUARANTINE_FILE="$1" ;;
    -k*) KEYWORDS+=("${1#-k}"); [ -n "${KEYWORDS[-1]}" ] || { shift; KEYWORDS+=("$1"); } ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) FILTERS+=("$1") ;;
  esac
  shift
done

export JACKAL_ROOT="${JACKAL_ROOT:-$REPO}"
export JACKAL_AGENT_DIR="${JACKAL_AGENT_DIR:-$REPO/pi}"

mapfile -t SUITES < <(find app -name '*.test.jac' | sort)
[ ${#SUITES[@]} -gt 0 ] || { echo "no suites found"; exit 2; }

match() { # match <suite>
  local s="$1" f k x
  for x in "${EXCLUDES[@]:-}"; do
    [ -z "$x" ] && continue
    case "$s" in *"$x"*) return 1 ;; esac
  done
  for f in "${FILTERS[@]:-}"; do
    [ -z "$f" ] && continue
    case "$s" in *"$f"*) ;; *) return 1 ;; esac
  done
  for k in "${KEYWORDS[@]:-}"; do
    [ -z "$k" ] && continue
    case "$(basename "$s")" in *"$k"*) ;; *) return 1 ;; esac
  done
  return 0
}

_exec_suite() { # _exec_suite <suite> <log>
  if command -v timeout >/dev/null 2>&1; then
    timeout --kill-after=30 "$TIMEOUT" "$JAC" test "$1" >"$2" 2>&1
  else
    "$JAC" test "$1" >"$2" 2>&1
  fi
}

run_suite() { # run_suite <suite>
  local s="$1"
  local name tag log rc secs
  name="${s#app/}"; name="${name%.test.jac}"
  tag="$(echo "$name" | tr '/' '_')"
  log="$LOGDIR/$tag.log"
  local start end
  start=$(date +%s)
  _exec_suite "$s" "$log"; rc=$?
  local status=""
  # Native crashes (SIGABRT/SIGSEGV, or timeout's "dumped core") get one
  # rerun; a pass on retry is reported FLAKY (non-fatal, listed).
  if [ $rc -ne 0 ] && { [ $rc -eq 134 ] || [ $rc -eq 139 ] || grep -q "dumped core" "$log"; }; then
    mv "$log" "$log.crash1"
    _exec_suite "$s" "$log"; rc=$?
    [ $rc -eq 0 ] && status=FLAKY
  fi
  end=$(date +%s)
  secs=$((end - start))
  if [ -n "$status" ]; then :
  elif [ $rc -eq 0 ]; then status=PASS
  elif [ $rc -eq 124 ] || [ $rc -eq 137 ]; then status="TIMEOUT($rc)"
  else status=FAIL; fi
  printf '%s %s %ss %s\n' "$status" "$name" "$secs" "$log"
  [ "$status" = PASS ] || [ "$status" = FLAKY ]
}

PASSED=0; FAILED=0; TIMEOUTS=0
FAILED_NAMES=()
declare -a RESULTS

if [ "$JOBS" -gt 1 ]; then
  pids=(); pjobs=()
  for s in "${SUITES[@]}"; do
    match "$s" || continue
    run_suite "$s" >"$LOGDIR/.$(echo "${s#app/}" | tr '/' '_').status" &
    pids+=($!); pjobs+=("$s")
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
      wait -n; rc=$?
      for i in "${!pids[@]}"; do
        if ! kill -0 "${pids[$i]}" 2>/dev/null; then
          wait "${pids[$i]}" 2>/dev/null
          line="$(cat "$LOGDIR/.$(echo "${pjobs[$i]#app/}" | tr '/' '_').status")"
          RESULTS+=("$line")
          case "$line" in
            PASS*|FLAKY*) PASSED=$((PASSED+1)) ;;
            TIMEOUT*) TIMEOUTS=$((TIMEOUTS+1)); FAILED_NAMES+=("${pjobs[$i]}") ;;
            *) FAILED=$((FAILED+1)); FAILED_NAMES+=("${pjobs[$i]}") ;;
          esac
          unset 'pids[$i]'; unset 'pjobs[$i]'
        fi
      done
    done
  done
  wait
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" 2>/dev/null
    line="$(cat "$LOGDIR/.$(echo "${pjobs[$i]#app/}" | tr '/' '_').status")"
    RESULTS+=("$line")
    case "$line" in
      PASS*|FLAKY*) PASSED=$((PASSED+1)) ;;
      TIMEOUT*) TIMEOUTS=$((TIMEOUTS+1)); FAILED_NAMES+=("${pjobs[$i]}") ;;
      *) FAILED=$((FAILED+1)); FAILED_NAMES+=("${pjobs[$i]}") ;;
    esac
  done
else
  for s in "${SUITES[@]}"; do
    match "$s" || continue
    if line=$(run_suite "$s"); then
      PASSED=$((PASSED+1))
    else
      case "$line" in
        TIMEOUT*) TIMEOUTS=$((TIMEOUTS+1)) ;;
        *) FAILED=$((FAILED+1)) ;;
      esac
      FAILED_NAMES+=("$s")
    fi
    RESULTS+=("$line")
    printf '%s\n' "$line"
    if [ "$FAIL_FAST" -eq 1 ] && [ $((FAILED + TIMEOUTS)) -gt 0 ]; then
      echo "fail-fast: stopping"; break
    fi
  done
fi

declare -A QUAR=()
if [ -n "$QUARANTINE_FILE" ] && [ -f "$QUARANTINE_FILE" ]; then
  while IFS= read -r q; do
    q="${q%%#*}"; q="$(echo "$q" | xargs)"
    [ -n "$q" ] && QUAR["$q"]=1
  done < "$QUARANTINE_FILE"
fi

# Recount from RESULTS ("STATUS name secs log") with quarantine applied.
PASSED=0; FAILED=0; TIMEOUTS=0; XFAIL=0
FAILED_NAMES=(); XPASS_NAMES=(); FLAKY_NAMES=()
for line in "${RESULTS[@]:-}"; do
  [ -z "$line" ] && continue
  st="${line%% *}"; rest="${line#* }"; nm="${rest%% *}"
  if [ "$st" = PASS ] || [ "$st" = FLAKY ]; then
    PASSED=$((PASSED+1))
    [ "$st" = FLAKY ] && FLAKY_NAMES+=("$nm")
    [ -n "${QUAR[$nm]:-}" ] && XPASS_NAMES+=("$nm")
  elif [ -n "${QUAR[$nm]:-}" ]; then
    XFAIL=$((XFAIL+1))
  else
    case "$st" in TIMEOUT*) TIMEOUTS=$((TIMEOUTS+1)) ;; *) FAILED=$((FAILED+1)) ;; esac
    FAILED_NAMES+=("$nm")
  fi
done

echo
echo "================ jackal test summary ================"
if [ "$JOBS" -gt 1 ]; then printf '%s\n' "${RESULTS[@]}" | sort -k2; fi
echo "suites: $((PASSED + FAILED + TIMEOUTS + XFAIL))  pass: $PASSED  fail: $FAILED  timeout: $TIMEOUTS  xfail(quarantined): $XFAIL"
if [ ${#FAILED_NAMES[@]} -gt 0 ]; then
  echo "failing:"; printf '  %s\n' "${FAILED_NAMES[@]}"
fi
if [ ${#FLAKY_NAMES[@]} -gt 0 ]; then
  echo "flaky (crashed once, passed on retry):"; printf '  %s\n' "${FLAKY_NAMES[@]}"
fi
if [ ${#XPASS_NAMES[@]} -gt 0 ]; then
  echo "quarantined but passing (remove from $QUARANTINE_FILE):"; printf '  %s\n' "${XPASS_NAMES[@]}"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### jackal tests: pass $PASSED · fail $FAILED · timeout $TIMEOUTS · xfail $XFAIL"
    for n in "${FAILED_NAMES[@]:-}"; do [ -n "$n" ] && echo "- :x: \`$n\`"; done
    for n in "${FLAKY_NAMES[@]:-}"; do [ -n "$n" ] && echo "- :warning: \`$n\` crashed once, passed on retry"; done
    for n in "${XPASS_NAMES[@]:-}"; do [ -n "$n" ] && echo "- :tada: \`$n\` passes — unquarantine"; done
  } >> "$GITHUB_STEP_SUMMARY"
fi
[ $FAILED -eq 0 ] && [ $TIMEOUTS -eq 0 ]
