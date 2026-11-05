#!/usr/bin/env bash
# Fast js2jac bridge harness (Jackal-local copy).
# Converts TS/TSX source on stdin to an emitted-Jac JSON envelope.
# Usage:  echo '<source>' | ./js2jac_bridge.sh [language] [path]
#   language: tsx (default) | ts | jsx | js
#   path:     virtual path label (default: App.tsx)
set -euo pipefail
LANG="${1:-tsx}"; PPATH="${2:-App.tsx}"
DIR="${JS2JAC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../js2jac" && pwd)}"
SRC="$(cat)"
# 1. JSON-encode the source, build the parse request, parse -> AST envelope
AST_ENV=$(printf '%s' "$SRC" | node -e 'let s=""; process.stdin.setEncoding("utf8"); process.stdin.on("data",x=>s+=x); process.stdin.on("end",()=>process.stdout.write(JSON.stringify({protocolVersion:1,language:process.argv[1],source:s})))' "$LANG" | bun "$DIR/parser_bridge.mjs" 2>/dev/null)
# 2. build the convert request {protocolVersion, ast, path}, convert -> Jac envelope
CONV_REQ=$(node -e 'let s=""; process.stdin.setEncoding("utf8"); process.stdin.on("data",x=>s+=x); process.stdin.on("end",()=>{const e=JSON.parse(s); process.stdout.write(JSON.stringify({protocolVersion:1,ast:e.ast,path:process.argv[1]}))})' "$PPATH" <<<"$AST_ENV")
printf '%s' "$CONV_REQ" | bun "$DIR/convert_bridge.mjs" | node -e 'let s=""; process.stdin.setEncoding("utf8"); process.stdin.on("data",x=>s+=x); process.stdin.on("end",()=>process.stdout.write(JSON.stringify(JSON.parse(s),null,2)+"\n"))'
