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

sug "$S" --dismiss review >/dev/null; sug "$S" --dismiss review >/dev/null; sug "$S" --dismiss bf >/dev/null
check "AC-3 dismissed feature prints nothing, list is idempotent" '[ "$(sug "$S" review)" = "rc=0" ] && grep -qx "  dismissed: \[review, bf\]" "$S/config.yaml" && [ "$(grep -c "^plugins:" "$S/config.yaml")" = 1 ]'
mkdir -p "$TMP/bare" && printf 'version: 1\nproject:\n  name: x\n' > "$TMP/bare/config.yaml"
sug "$TMP/bare" --dismiss sync >/dev/null
check "AC-3 --dismiss creates the plugins block" 'grep -qx "plugins:" "$TMP/bare/config.yaml" && grep -qx "  dismissed: \[sync\]" "$TMP/bare/config.yaml" && [ "$(sug "$TMP/bare" sync)" = "rc=0" ]'
mkdir -p "$TMP/blk" && printf 'plugins:\n  dismissed:\n    - review\n' > "$TMP/blk/config.yaml" && cp "$TMP/blk/config.yaml" "$TMP/blk.orig"
check "AC-3 a block-list dismissed is left alone, not corrupted" '[ "$(sug "$TMP/blk" --dismiss bf 2>/dev/null)" = "rc=0" ] && cmp -s "$TMP/blk/config.yaml" "$TMP/blk.orig"'

check "AC-4 unknown feature, missing config and Codex print nothing" '[ "$(sug "$S" nope 2>&1)" = "rc=0" ] && [ "$(sug "$TMP/none" review 2>&1)" = "rc=0" ] && [ "$(CODEX_THREAD_ID=t sug "$S" review 2>&1)" = "rc=0" ]'

check "AC-5 session-start sources the shared lib, no copy of installed()" 'grep -q "lib/plugins.sh" "$PLUGIN_DIR/hooks/session-start" && ! grep -q "^installed()" "$PLUGIN_DIR/hooks/session-start"'
"$BIN/specclaw-init" "$TMP/h" demo d >/dev/null
sed -i.bak '/^github:/,/^[a-z]/ s/^  sync: false/  sync: true/' "$TMP/h/.specclaw/config.yaml"
hook() { (cd "$TMP/h" && PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$PLUGIN_DIR/hooks/session-start"); }
before="$(hook)"; sug "$TMP/h/.specclaw" --dismiss sync >/dev/null; after="$(hook)"
check "AC-5 hook names a missing plugin until its feature is dismissed" 'grep -q "install specclaw-sync@chan4lk" <<<"$before" && ! grep -q "install specclaw-sync@chan4lk" <<<"$after"'

mkdir -p "$S/changes/001-x"
"$BIN/specclaw-timer" start "$S" 001-x T1 --kind task >/dev/null
"$BIN/specclaw-log-learning" "$S" 001-x pattern high "say \"hi\" $(printf 'a\rb\033c')" 'do it' >/dev/null
"$BIN/specclaw-timer" stop "$S" 001-x T1 >/dev/null
lesson="$(grep '"kind":"lesson"' "$S/changes/001-x/timeline.jsonl" | sed -E 's/"at":"[0-9TZ:-]+"/"at":"X"/')"
check "AC-6 log-learning appends one lesson line, control characters blanked" '[ "$lesson" = '"'"'{"kind":"lesson","at":"X","category":"pattern","priority":"high","detail":"say \"hi\" a b c","action":"do it"}'"'"' ]'
check "AC-6 timer report does not call the lesson line unparseable" '! "$BIN/specclaw-timer" report "$S" 001-x 2>&1 >/dev/null | grep -q unparseable'

check "AC-7 every call site names specclaw-suggest, verify no longer skips silently" '(for f in skills/verify/SKILL.md references/full/verify.md skills/status/SKILL.md references/full/status.md skills/propose/SKILL.md references/full/propose.md skills/init/SKILL.md references/full/init.md; do grep -q "specclaw-suggest" "$PLUGIN_DIR/$f" || exit 1; done) && ! grep -qiE "skip(s)? (it )?silently" "$PLUGIN_DIR/skills/verify/SKILL.md" "$PLUGIN_DIR/references/full/verify.md"'

echo
[ "$FAILS" -eq 0 ] && echo "All suggest tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
