#!/usr/bin/env bash
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0

if ! command -v bun >/dev/null 2>&1; then
  echo "FAIL: bun is required to run the specclaw-dash mod tests"
  exit 1
fi

(cd "$PLUGIN_DIR" && bun test ./tests/*.spec.ts) || FAILS=$((FAILS + 1))

# AC-7: the pane is read only. The mod may call only the read methods of $.fs, and never $.process.
# A grep that finds no $.fs call at all means the check did not run, which is a failure, not a pass.
calls="$(grep -rnoE '\$\.(fs\.[a-zA-Z]+|process)' "$PLUGIN_DIR/hooks" 2>/dev/null)"
if [ -z "$calls" ]; then
  echo "FAIL: AC-7 found no \$.fs call in $PLUGIN_DIR/hooks: the check did not run"
  FAILS=$((FAILS + 1))
elif grep -vE '\$\.fs\.(exists|read|list|stat)$' <<<"$calls"; then
  echo "FAIL: AC-7 the mod calls a non-read \$.fs method or \$.process"
  FAILS=$((FAILS + 1))
else
  echo "PASS: AC-7 the mod calls only \$.fs exists/read/list/stat and no \$.process"
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "FAIL: claude is required for plugin validate and plugin test (npm i -g @anthropic-ai/claude-code)"
  exit 1
fi

claude plugin validate "$PLUGIN_DIR" || FAILS=$((FAILS + 1))
claude plugin test "$PLUGIN_DIR" || FAILS=$((FAILS + 1))

[ "$FAILS" -eq 0 ] && echo "ALL PASS" || { echo "$FAILS step(s) failed"; exit 1; }
