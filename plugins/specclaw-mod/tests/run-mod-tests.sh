#!/usr/bin/env bash
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0

if ! command -v bun >/dev/null 2>&1; then
  echo "FAIL: bun is required to run the specclaw-mod tests"
  exit 1
fi

(cd "$PLUGIN_DIR" && bun test ./tests/*.spec.ts) || FAILS=$((FAILS + 1))

if ! command -v claude >/dev/null 2>&1; then
  echo "FAIL: claude is required for plugin validate and plugin test (npm i -g @anthropic-ai/claude-code)"
  exit 1
fi

claude plugin validate "$PLUGIN_DIR" || FAILS=$((FAILS + 1))
claude plugin test "$PLUGIN_DIR" || FAILS=$((FAILS + 1))

[ "$FAILS" -eq 0 ] && echo "ALL PASS" || { echo "$FAILS step(s) failed"; exit 1; }
