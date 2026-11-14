#!/usr/bin/env bash
# run-suggest-tests.sh — change 059: specclaw-suggest and the lesson line, one case per AC.
# shellcheck disable=SC2016  # check() evals its single-quoted condition later, by design
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$PLUGIN_DIR/bin"
FAILS=0
ok() { echo "PASS: $1"; }
ko() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unset CODEX_THREAD_ID CODEX_SANDBOX
ROOT="$TMP/cache/chan4lk/specclaw/0.9.7"
mkdir -p "$ROOT"
"$BIN/specclaw-init" "$TMP/p" demo d >/dev/null
S="$TMP/p/.specclaw"
sug() { PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$ROOT" "$BIN/specclaw-suggest" "$@"; echo "rc=$?"; }

check "AC-1 missing plugin prints the exact tip" '[ "$(sug "$S" review)" = "Tip: a review loop checks each change against your project'"'"'s rules before its PR. Install: /plugin install specclaw-review@chan4lk (say \"no\" to never see this again)
rc=0" ]'

mkdir -p "$TMP/cache/chan4lk/specclaw-fleet/0.9.7/bin" && : > "$TMP/cache/chan4lk/specclaw-fleet/0.9.7/bin/specclaw-fleet"
mkdir -p "$TMP/onpath" && printf '#!/bin/sh\n' > "$TMP/onpath/specclaw-gh-sync" && chmod +x "$TMP/onpath/specclaw-gh-sync"
check "AC-2 installed in the plugin cache prints nothing" '[ "$(sug "$S" fleet)" = "rc=0" ]'
check "AC-2 installed on PATH prints nothing" '[ "$(PATH="$TMP/onpath:/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$ROOT" "$BIN/specclaw-suggest" "$S" sync; echo "rc=$?")" = "rc=0" ]'

sug "$S" --dismiss dash >/dev/null; sug "$S" --dismiss dash >/dev/null; sug "$S" --dismiss bf >/dev/null
check "AC-3 dismissed feature prints nothing, list is idempotent" '[ "$(sug "$S" dash)" = "rc=0" ] && grep -qx "  dismissed: \[dash, bf\]" "$S/config.yaml" && [ "$(grep -c "^plugins:" "$S/config.yaml")" = 1 ]'
printf 'version: 1\nproject:\n  name: x\n' > "$TMP/bare.yaml"; mkdir -p "$TMP/bare" && mv "$TMP/bare.yaml" "$TMP/bare/config.yaml"
sug "$TMP/bare" --dismiss sync >/dev/null
check "AC-3 --dismiss creates the plugins block" 'grep -qx "plugins:" "$TMP/bare/config.yaml" && grep -qx "  dismissed: \[sync\]" "$TMP/bare/config.yaml" && [ "$(sug "$TMP/bare" sync)" = "rc=0" ]'

check "AC-4 unknown feature, missing config and Codex print nothing" '[ "$(sug "$S" nope 2>&1)" = "rc=0" ] && [ "$(sug "$TMP/none" review 2>&1)" = "rc=0" ] && [ "$(CODEX_THREAD_ID=t sug "$S" review 2>&1)" = "rc=0" ]'

check "AC-5 session-start sources the shared lib, no copy of installed()" 'grep -q "lib/plugins.sh" "$PLUGIN_DIR/hooks/session-start" && ! grep -q "^installed()" "$PLUGIN_DIR/hooks/session-start"'

mkdir -p "$S/changes/001-x"
"$BIN/specclaw-timer" start "$S" 001-x T1 --kind task >/dev/null
"$BIN/specclaw-log-learning" "$S" 001-x pattern high 'say "hi"' 'do it' >/dev/null
"$BIN/specclaw-timer" stop "$S" 001-x T1 >/dev/null
check "AC-6 log-learning appends one lesson line with its fields" 'python3 -c "import json,sys; l=[json.loads(x) for x in open(sys.argv[1]) if \"lesson\" in x]; assert len(l)==1 and {k:l[0][k] for k in (\"kind\",\"category\",\"priority\",\"detail\",\"action\")}=={\"kind\":\"lesson\",\"category\":\"pattern\",\"priority\":\"high\",\"detail\":\"say \\\"hi\\\"\",\"action\":\"do it\"} and l[0][\"at\"]" "$S/changes/001-x/timeline.jsonl"'
check "AC-6 timer report does not call the lesson line unparseable" '! "$BIN/specclaw-timer" report "$S" 001-x 2>&1 >/dev/null | grep -q unparseable'

check "AC-7 every call site names specclaw-suggest" '(for f in skills/verify/SKILL.md references/full/verify.md skills/status/SKILL.md references/full/status.md skills/propose/SKILL.md references/full/propose.md skills/init/SKILL.md references/full/init.md; do grep -q "specclaw-suggest" "$PLUGIN_DIR/$f" || exit 1; done)'

echo
[ "$FAILS" -eq 0 ] && echo "All suggest tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
