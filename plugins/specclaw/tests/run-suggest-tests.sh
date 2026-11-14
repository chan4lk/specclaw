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
# Block-list variants: each row is a plugins block; review must read as dismissed, and --dismiss bf
# must leave exactly one inline list ending in bf with no stray items and the sibling key intact.
n=0
while IFS= read -r row; do
  n=$((n + 1)); d="$TMP/blk$n"; mkdir -p "$d"; printf "$row" > "$d/config.yaml"
  check "AC-3 block list row $n: dismissal honoured" '[ "$(sug "$d" review)" = "rc=0" ]'
  sug "$d" --dismiss bf >/dev/null
  check "AC-3 block list row $n: folded into one inline list" 'grep -qxE "  dismissed: \[(fleet, )?review(, fleet)?, bf\]" "$d/config.yaml" && ! grep -qE "^[[:space:]]+- " "$d/config.yaml" && { ! grep -q "other:" <<<"$row" || grep -qx "  other: 1" "$d/config.yaml"; } && { ! grep -q "next:" <<<"$row" || grep -qx "next: 1" "$d/config.yaml"; }'
done <<'ROWS'
plugins:\n  dismissed:\n    - review\n  other: 1\n
plugins:\n  dismissed:\n    - fleet\n\n    # note\n    - review\n  other: 1\n
plugins:\n  dismissed:\n    - "review"\n    - 'fleet'\n
plugins:\n  dismissed:\n    - review  # why\n  other: 1\n
plugins:\n  dismissed:\n  - review\nnext: 1\n
ROWS
mkdir -p "$TMP/hb/.specclaw" && printf 'github:\n  sync: true\nplugins:\n  dismissed:\n    - sync\n' > "$TMP/hb/.specclaw/config.yaml"
hb="$(cd "$TMP/hb" && PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$PLUGIN_DIR/hooks/session-start")"
mkdir -p "$TMP/hc/.specclaw" && printf 'github:\n  sync: true\n' > "$TMP/hc/.specclaw/config.yaml"
hc="$(cd "$TMP/hc" && PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$PLUGIN_DIR/hooks/session-start")"
check "AC-5 hook honours a block-list dismissal (control run without it shows the notice)" 'grep -q "install specclaw-sync@chan4lk" <<<"$hc" && grep -q "hookSpecificOutput" <<<"$hb" && ! grep -q "install specclaw-sync@chan4lk" <<<"$hb"'

# Every write-failure path of --dismiss: no config, temp file (read-only dir), reading the config
# (unreadable file), writing it back (read-only file). Each must say so on stderr, exit 0, change nothing.
for row in none:- rodir:555 unreadable:000 rofile:444; do
  name="${row%%:*}"; mode="${row#*:}"; d="$TMP/w-$name"
  if [ "$mode" != - ]; then
    mkdir -p "$d" && printf 'version: 1\n' > "$d/config.yaml" && cp "$d/config.yaml" "$d.orig"
    if [ "$name" = rodir ]; then chmod "$mode" "$d"; else chmod "$mode" "$d/config.yaml"; fi
  fi
  err="$(sug "$d" --dismiss review 2>&1)"
  chmod 755 "$d" 2>/dev/null; chmod 644 "$d/config.yaml" 2>/dev/null
  check "AC-3 --dismiss write failure ($name) says so, exit 0, config unchanged" 'grep -q "could not record dismissal of '"'"'review'"'"'" <<<"$err" && grep -q "rc=0" <<<"$err" && { [ "$mode" = - ] || cmp -s "$d/config.yaml" "$d.orig"; } && ! ls "$d"/config.yaml.?????? >/dev/null 2>&1'
done
# The write is a rename onto the real file, never a truncate-and-rewrite of it: the real file's inode
# changes (an in-place `cat >` keeps it), links stay links, the mode is kept. Relative, absolute and
# chained symlinks.
for kind in rel abs chain; do
  d="$TMP/ln-$kind"; mkdir -p "$d/real" && printf 'version: 1\n' > "$d/real/config.yaml" && chmod 640 "$d/real/config.yaml"
  case "$kind" in
    rel)   ln -s real/config.yaml "$d/config.yaml" ;;
    abs)   ln -s "$d/real/config.yaml" "$d/config.yaml" ;;
    chain) ln -s config.yaml "$d/real/hop.yaml" && ln -s real/hop.yaml "$d/config.yaml" ;;
  esac
  ino="$(ls -i "$d/real/config.yaml" | awk '{print $1}')"
  sug "$d" --dismiss review >/dev/null
  check "AC-3 --dismiss ($kind symlink) renames onto the real file, keeps the link and mode" '[ -L "$d/config.yaml" ] && grep -qx "  dismissed: \[review\]" "$d/real/config.yaml" && [ "$(ls -i "$d/real/config.yaml" | awk "{print \$1}")" != "$ino" ] && [ "$(ls -l "$d/real/config.yaml" | cut -c1-10)" = "-rw-r-----" ]'
done
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
"$BIN/specclaw-log-learning" "$S" 001-x spec_gap low d "$(printf 'q" s\\ b\b f\f x\001 end')" >/dev/null
check "AC-6 the action field is escaped too" 'grep -qF '"'"'"category":"spec_gap","priority":"low","detail":"d","action":"q\" s\\ b  f  x  end"}'"'"' "$S/changes/001-x/timeline.jsonl"'
check "AC-6 timer report does not call the lesson line unparseable" '! "$BIN/specclaw-timer" report "$S" 001-x 2>&1 >/dev/null | grep -q unparseable'

check "AC-7 every call site names specclaw-suggest, verify no longer skips silently" '(for f in skills/verify/SKILL.md references/full/verify.md skills/status/SKILL.md references/full/status.md skills/propose/SKILL.md references/full/propose.md skills/init/SKILL.md references/full/init.md; do grep -q "specclaw-suggest" "$PLUGIN_DIR/$f" || exit 1; done) && ! grep -qiE "skip(s)? (it )?silently" "$PLUGIN_DIR/skills/verify/SKILL.md" "$PLUGIN_DIR/references/full/verify.md"'

echo
[ "$FAILS" -eq 0 ] && echo "All suggest tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
