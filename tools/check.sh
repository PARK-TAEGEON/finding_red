#!/usr/bin/env bash
# Build + type check + Lune tests + map checks. Last line is CHECK PASS or CHECK FAIL.
# Tool binaries: $FR_BIN, else .tools/bin (from tools/setup.sh), else /home/claude/bin.
set -u
cd "$(dirname "$0")/.."
if [ -n "${FR_BIN:-}" ]; then BIN="$FR_BIN"
elif [ -x .tools/bin/rojo ]; then BIN=".tools/bin"
elif [ -x /home/claude/bin/rojo ]; then BIN="/home/claude/bin"
else echo "tools not found: run tools/setup.sh first"; echo "CHECK FAIL"; exit 1; fi
mkdir -p build
fail=0

step() { printf '\n== %s\n' "$1"; }

step "rojo build"
if "$BIN/rojo" build -o build/FindingRed.rbxl > build/rojo.log 2>&1; then
  echo "ok"
else
  cat build/rojo.log; fail=1
fi

step "type check (src/)"
"$BIN/rojo" sourcemap -o sourcemap.json > /dev/null 2>&1
"$BIN/luau-lsp" analyze \
  --definitions="$BIN/globalTypes.d.luau" \
  --sourcemap=sourcemap.json \
  src > build/analyze.log 2>&1
errors=$(grep -E "(TypeError|SyntaxError|UnknownGlobal|UnknownRequire)" build/analyze.log || true)
warnings=$(grep -cvE "(TypeError|SyntaxError|UnknownGlobal|UnknownRequire)" build/analyze.log || true)
if [ -n "$errors" ]; then
  echo "$errors"; fail=1
else
  echo "ok (lint warnings: ${warnings:-0}, see build/analyze.log)"
fi

step "lune tests (tests/*.spec.luau)"
shopt -s nullglob
for spec in tests/*.spec.luau; do
  if out=$("$BIN/lune" run "$spec" 2>&1); then
    echo "ok   $spec — $(echo "$out" | tail -1)"
  else
    echo "FAIL $spec"; echo "$out" | tail -20; fail=1
  fi
done

if [ -f tools/dump_maps.luau ]; then
  step "map dump"
  if "$BIN/lune" run tools/dump_maps.luau > build/maps.log 2>&1; then
    echo "ok — $(tail -1 build/maps.log)"
  else
    tail -20 build/maps.log; fail=1
  fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "CHECK PASS"; else echo "CHECK FAIL"; fi
exit "$fail"
