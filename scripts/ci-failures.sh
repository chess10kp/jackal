#!/bin/bash
# Summarize failing suites from a GitHub Actions app-tests run.
#
# Usage:
#   scripts/ci-failures.sh            # latest app-tests run on the current branch
#   scripts/ci-failures.sh RUN_ID
#
# Downloads the testlogs-* artifacts into .ci-logs/<run>/ and prints, per
# failing suite, the first compiler errors / assertion lines. Also prints
# `jac check` errors from the check job.
set -u
cd "$(dirname "$0")/.."
RUN="${1:-$(gh run list -w "App tests" -b "$(git branch --show-current)" -L 1 --json databaseId -q '.[0].databaseId')}"
[ -n "$RUN" ] || { echo "no run found"; exit 2; }
OUT=".ci-logs/$RUN"
rm -rf "$OUT"; mkdir -p "$OUT"
echo "run $RUN: $(gh run view "$RUN" --json status,conclusion -q '.status + " " + .conclusion')"
gh run view "$RUN" --json jobs -q '.jobs[] | "  " + .name + ": " + (.conclusion // .status)'
gh run download "$RUN" -D "$OUT" >/dev/null 2>&1 || true

for f in $(find "$OUT" -name '*.log' | sort); do
  if tail -3 "$f" | grep -qE '^[0-9]+ passed in'; then continue; fi
  echo
  echo "=== $(basename "$(dirname "$f")")/$(basename "$f" .log)"
  grep -E '^error\[|^ *--> |FAILED |AssertionError|^E  |Error:|dumped core|No bytecode|TIMEOUT' "$f" | head -12 | cut -c1-240
done

J=$(gh run view "$RUN" --json jobs -q '.jobs[] | select(.name=="check" and .conclusion=="failure") | .databaseId')
if [ -n "$J" ]; then
  echo
  echo "=== jac check"
  gh run view --job="$J" --log 2>/dev/null | sed 's/^[^\t]*\t[^\t]*\t[^ ]* //' \
    | grep -A1 'Error: error\[' | grep -v '^--$' | paste - - | sort -u | head -30 | cut -c1-240
fi
