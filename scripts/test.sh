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

JAC="${JAC:-$REPO/jac}"
if [ ! -x "$JAC" ]; then JAC=jac; fi
TIMEOUT="${TIMEOUT:-600}"
JOBS=1
# `wait -n` (parallel mode) needs bash 4.3+; stock macOS bash 3.2 degrades
# to sequential instead of silently matching zero suites.
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 3 ]; }; then
  JAC_SERIAL_ONLY=1
fi
FAIL_FAST=0
# Sentinel empty element: bash 3.2 mishandles ${arr[@]+"${arr[@]}"} for
# multi-element arrays (joins them into one word), so arrays start with ""
# and every loop skips empties.
FILTERS=("")
KEYWORDS=("")
EXCLUDES=("")
QUARANTINE_FILE=""
FAIL_ON_XPASS=0
LOGDIR="$REPO/.testlogs"
mkdir -p "$LOGDIR"

while [ $# -gt 0 ]; do
  case "$1" in
    -j*)
      JOBS="${1#-j}"
      if [ -z "$JOBS" ]; then
        [ $# -ge 2 ] || { echo "test.sh: -j needs a number" >&2; exit 2; }
        shift
        JOBS="$1"
      fi
      ;;
    --fail-fast) FAIL_FAST=1 ;;
    --exclude) shift; [ $# -ge 1 ] || { echo "test.sh: --exclude needs a path" >&2; exit 2; }; EXCLUDES+=("$1") ;;
    --quarantine) shift; [ $# -ge 1 ] || { echo "test.sh: --quarantine needs a file" >&2; exit 2; }; QUARANTINE_FILE="$1" ;;
    --fail-on-xpass) FAIL_ON_XPASS=1 ;;
    -k*)
      # `KEYWORDS[-1]` is bash 4.3+; stock macOS 3.2 rejects any negative
      # subscript, so compute the last index explicitly.
      KEYWORDS+=("${1#-k}")
      if [ -z "${KEYWORDS[$((${#KEYWORDS[@]} - 1))]}" ]; then
        [ $# -ge 2 ] || { echo "test.sh: -k needs a keyword" >&2; exit 2; }
        shift
        KEYWORDS+=("$1")
      fi
      ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) FILTERS+=("$1") ;;
  esac
  shift
done

case "$JOBS" in
  ''|*[!0-9]*) echo "test.sh: -j needs a positive number (got '$JOBS')" >&2; exit 2 ;;
esac

export JACKAL_ROOT="${JACKAL_ROOT:-$REPO}"
export JACKAL_AGENT_DIR="${JACKAL_AGENT_DIR:-$REPO/pi}"

# bash 3.2 (stock macOS) has no mapfile; a read loop keeps the runner portable.
SUITES=()
while IFS= read -r _suite; do
  SUITES+=("$_suite")
done < <(find app -name '*.test.jac' -not -path '*/.jac/*' | sort)
[ ${#SUITES[@]} -gt 0 ] || { echo "no suites found"; exit 2; }
if [ "${JAC_SERIAL_ONLY:-0}" = "1" ] && [ "$JOBS" -gt 1 ]; then
  echo "test.sh: bash ${BASH_VERSION%%(*} lacks 'wait -n'; running sequentially" >&2
  JOBS=1
fi

match() { # match <suite> — filters/keywords are unions; excludes win
  local s="$1" f k x matched
  for x in "${EXCLUDES[@]}"; do
    [ -z "$x" ] && continue
    case "$s" in *"$x"*) return 1 ;; esac
  done
  matched=0
  for f in "${FILTERS[@]}"; do
    [ -z "$f" ] && continue
    case "$s" in *"$f"*) matched=1 ;; esac
  done
  if [ -n "${FILTERS[*]}" ] && [ "$matched" -eq 0 ]; then
    return 1
  fi
  matched=0
  for k in "${KEYWORDS[@]}"; do
    [ -z "$k" ] && continue
    case "$(basename "$s")" in *"$k"*) matched=1 ;; esac
  done
  if [ -n "${KEYWORDS[*]}" ] && [ "$matched" -eq 0 ]; then
    return 1
  fi
  return 0
}

_exec_suite() { # _exec_suite <suite> <log>
  # Suites run with cwd=app/ (the app project): module resolution, placement
  # pins, and the app venv all resolve there. Running from the repo root
  # makes cross-package imports (tui.*, core.*) resolve against legacy
  # root-level shadow dirs and the root venv, skipping or crashing suites.
  local suite="$1" log="$2" rel="${1#app/}"
  if command -v timeout >/dev/null 2>&1; then
    (cd "$REPO/app" && timeout --kill-after=30 "$TIMEOUT" "$JAC" test "$rel") >"$log" 2>&1
  else
    (cd "$REPO/app" && "$JAC" test "$rel") >"$log" 2>&1
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
declare -a RESULTS=("")

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

# bash 3.2 has no associative arrays: keep the list newline-delimited.
QUAR_LIST="
"
_is_quarantined() { # _is_quarantined <suite-name>
  case "$QUAR_LIST" in
    *"
$1
"*) return 0 ;;
  esac
  return 1
}
if [ -n "$QUARANTINE_FILE" ] && [ -f "$QUARANTINE_FILE" ]; then
  while IFS= read -r q; do
    q="${q%%#*}"; q="$(echo "$q" | xargs)"
    [ -n "$q" ] && QUAR_LIST="$QUAR_LIST$q
"
  done < "$QUARANTINE_FILE"
fi

# Recount from RESULTS ("STATUS name secs log") with quarantine applied.
PASSED=0; FAILED=0; TIMEOUTS=0; XFAIL=0
FAILED_NAMES=(""); XPASS_NAMES=(""); FLAKY_NAMES=("")
for line in "${RESULTS[@]}"; do
  [ -z "$line" ] && continue
  st="${line%% *}"; rest="${line#* }"; nm="${rest%% *}"
  if [ "$st" = PASS ] || [ "$st" = FLAKY ]; then
    PASSED=$((PASSED+1))
    [ "$st" = FLAKY ] && FLAKY_NAMES+=("$nm")
    _is_quarantined "$nm" && XPASS_NAMES+=("$nm")
  elif _is_quarantined "$nm"; then
    XFAIL=$((XFAIL+1))
  else
    case "$st" in TIMEOUT*) TIMEOUTS=$((TIMEOUTS+1)) ;; *) FAILED=$((FAILED+1)) ;; esac
    FAILED_NAMES+=("$nm")
  fi
done

echo
echo "================ jackal test summary ================"
if [ "$JOBS" -gt 1 ] && [ -n "${RESULTS[*]}" ]; then
  printf '%s\n' "${RESULTS[@]}" | sort -k2
fi
echo "suites: $((PASSED + FAILED + TIMEOUTS + XFAIL))  pass: $PASSED  fail: $FAILED  timeout: $TIMEOUTS  xfail(quarantined): $XFAIL"
if [ -n "${FAILED_NAMES[*]}" ]; then
  echo "failing:"; for n in "${FAILED_NAMES[@]}"; do [ -n "$n" ] && printf '  %s\n' "$n"; done
fi
if [ -n "${FLAKY_NAMES[*]}" ]; then
  echo "flaky (crashed once, passed on retry):"; for n in "${FLAKY_NAMES[@]}"; do [ -n "$n" ] && printf '  %s\n' "$n"; done
fi
if [ -n "${XPASS_NAMES[*]}" ]; then
  echo "quarantined but passing (remove from $QUARANTINE_FILE):"; for n in "${XPASS_NAMES[@]}"; do [ -n "$n" ] && printf '  %s\n' "$n"; done
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### jackal tests: pass $PASSED · fail $FAILED · timeout $TIMEOUTS · xfail $XFAIL"
    for n in "${FAILED_NAMES[@]}"; do [ -n "$n" ] && echo "- :x: \`$n\`"; done
    for n in "${FLAKY_NAMES[@]}"; do [ -n "$n" ] && echo "- :warning: \`$n\` crashed once, passed on retry"; done
    for n in "${XPASS_NAMES[@]}"; do [ -n "$n" ] && echo "- :tada: \`$n\` passes — unquarantine"; done
  } >> "$GITHUB_STEP_SUMMARY"
fi
if [ $FAILED -eq 0 ] && [ $TIMEOUTS -eq 0 ]; then
  if [ "$FAIL_ON_XPASS" -eq 1 ] && [ ${#XPASS_NAMES[@]} -gt 0 ]; then
    echo "fail-on-xpass: ${#XPASS_NAMES[@]} quarantined suite(s) now pass" >&2
    exit 1
  fi
  exit 0
fi
exit 1
