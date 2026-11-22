#!/bin/sh
# Run `neojac test` one module at a time under a memory cap + timeout.
# Usage: scripts/neojac-test-each.sh <outdir> <module.jac>...   (run from app/)
out=$1; shift
mkdir -p "$out"
for m in "$@"; do
  log="$out/$(echo "$m" | tr '/' '_').log"
  sudo systemd-run --quiet --scope -p MemoryMax=4G -p MemorySwapMax=0 --uid="$(id -u)" --gid="$(id -g)" \
    --setenv=PATH="$PATH" --setenv=HOME="$HOME" --working-directory="$PWD" \
    timeout 600 neojac test "$m" > "$log" 2>&1
  echo "$m rc=$? $(grep -aE '^[a-z_/0-9]+\.jac: ' "$log" | tail -1)" >> "$out/summary.txt"
done
echo DONE >> "$out/summary.txt"
