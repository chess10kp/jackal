#!/bin/sh
# Run one module's tests one name at a time (-k) under a memory cap + timeout.
# Usage: scripts/neojac-test-k.sh <outdir> <module.jac> <name>...   (run from app/)
out=$1; m=$2; shift 2
mkdir -p "$out"
for k in "$@"; do
  sudo systemd-run --quiet --scope -p MemoryMax=3G -p MemorySwapMax=0 --uid="$(id -u)" --gid="$(id -g)" \
    --setenv=PATH="$PATH" --setenv=HOME="$HOME" --working-directory="$PWD" \
    timeout 120 neojac test "$m" -k "$k" > "$out/k.log" 2>&1
  echo "[$k] rc=$? $(grep -aE '^[a-z_/0-9]+\.jac: ' "$out/k.log" | tail -1)" >> "$out/summary.txt"
done
echo DONE >> "$out/summary.txt"
