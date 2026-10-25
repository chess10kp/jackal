#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
if [[ ! -x ./jac ]]; then
  echo "workspace Jac binary missing; run ./scripts/setup-vendor-jac.sh with Zig 0.16.0" >&2
  exit 127
fi
exec ./jac run app/run.jac "$@"
