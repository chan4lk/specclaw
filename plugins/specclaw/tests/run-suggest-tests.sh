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
check "AC-3 dismissed feature prints nothing, list is idempotent" '[ "$(sug "$S" review)" = "rc=0" ] && grep -qE "^  dismissed: \[review, bf\]( |$)" "$S/config.yaml" && [ "$(grep -c "^plugins:" "$S/config.yaml")" = 1 ]'
mkdir -p "$TMP/bare" && printf 'version: 1\nproject:\n  name: x\n' > "$TMP/bare/config.yaml"
sug "$TMP/bare" --dismiss sync >/dev/null
check "AC-3 --dismiss keeps the template's comment on the dismissed line" 'grep -qE "^  dismissed: \[review, bf\][[:space:]]+# any of:" "$S/config.yaml"'
check "AC-3 --dismiss creates the plugins block" 'grep -qx "plugins:" "$TMP/bare/config.yaml" && grep -qx "  dismissed: \[sync\]" "$TMP/bare/config.yaml" && [ "$(sug "$TMP/bare" sync)" = "rc=0" ]'
# Block-list variants: each row is a plugins block; review must read as dismissed, and --dismiss bf
# must leave exactly one inline list ending in bf with no stray items and the sibling key intact.
n=0
while IFS= read -r row; do
  n=$((n + 1)); d="$TMP/blk$n"; mkdir -p "$d"; printf "$row" > "$d/config.yaml"
  check "AC-3 block list row $n: dismissal honoured" '[ "$(sug "$d" review)" = "rc=0" ]'
  sug "$d" --dismiss bf >/dev/null
  check "AC-3 block list row $n: folded into one inline list" 'tr -d "\r" < "$d/config.yaml" | grep -qxE "  dismissed: \[(fleet, )?review(, fleet)?, bf\]" && ! grep -qE "^[[:space:]]+- " "$d/config.yaml" && { ! grep -q "other:" <<<"$row" || tr -d "\r" < "$d/config.yaml" | grep -qx "  other: 1"; } && { ! grep -q "next:" <<<"$row" || grep -qx "next: 1" "$d/config.yaml"; }'
done <<'ROWS'
plugins:\n  dismissed:\n    - review\n  other: 1\n
plugins:\n  dismissed:\n    - fleet\n\n    # note\n    - review\n  other: 1\n
plugins:\n  dismissed:\n    - "review"\n    - 'fleet'\n
plugins:\n  dismissed:\n    - review  # why\n  other: 1\n
plugins:\n  dismissed:\n  - review\nnext: 1\n
plugins:\r\n  dismissed:\r\n    - review\r\n  other: 1\r\n
plugins:\r\n  dismissed: [review]\r\n
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
for kind in rel abs chain up dirlink; do
  d="$TMP/ln-$kind"; mkdir -p "$d/real" && printf 'version: 1\n' > "$d/real/config.yaml" && chmod 640 "$d/real/config.yaml"
  case "$kind" in
    rel)   ln -s real/config.yaml "$d/config.yaml" ;;
    abs)   ln -s "$d/real/config.yaml" "$d/config.yaml" ;;
    chain) ln -s config.yaml "$d/real/hop.yaml" && ln -s real/hop.yaml "$d/config.yaml" ;;
    up)    mkdir -p "$d/sib" && ln -s ../real/config.yaml "$d/sib/config.yaml" && ln -s sib/config.yaml "$d/config.yaml" ;;
    dirlink) rm -rf "$d.dir" && mv "$d/real" "$d.dir" && ln -s "$d.dir" "$d/real" && ln -s real/config.yaml "$d/config.yaml" ;;
  esac
  ino="$(ls -iL "$d/real/config.yaml" | awk '{print $1}')"
  sug "$d" --dismiss review >/dev/null
  check "AC-3 --dismiss ($kind symlink) renames onto the real file, keeps the link and mode" '[ -L "$d/config.yaml" ] && grep -qx "  dismissed: \[review\]" "$d/real/config.yaml" && [ "$(ls -iL "$d/real/config.yaml" | awk "{print \$1}")" != "$ino" ] && [ "$(ls -lL "$d/real/config.yaml" | cut -c1-10)" = "-rw-r-----" ]'
done
# A late failure: the temp copy exists and the rename onto the real file fails (mv stubbed to fail).
# The original bytes survive and no temp file is left behind.
d="$TMP/late"; mkdir -p "$d" "$TMP/failmv" && printf 'version: 1\n' > "$d/config.yaml" && cp "$d/config.yaml" "$d.orig"
printf '#!/bin/sh\n[ -f "$1" ] && grep -qx "  dismissed: \\\\[review\\\\]" "$1" && echo called >> "%s"\nexit 1\n' "$TMP/mv-called" > "$TMP/failmv/mv" && chmod +x "$TMP/failmv/mv"
err="$(PATH="$TMP/failmv:/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$ROOT" "$BIN/specclaw-suggest" "$d" --dismiss review 2>&1; echo "rc=$?")"
check "AC-3 --dismiss late rename failure keeps the original and cleans up" '[ "$(cat "$TMP/mv-called" 2>/dev/null)" = called ] && grep -q "could not record dismissal" <<<"$err" && grep -q "rc=0" <<<"$err" && cmp -s "$d/config.yaml" "$d.orig" && ! ls "$d"/config.yaml.?????? >/dev/null 2>&1'
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

# 062 AC-8: specclaw-dash ships no command; it is found by its manifest, next to core or in the cache.
check "062 AC-8 dash missing prints the dash tip" '[ "$(sug "$S" dash)" = "Tip: a /dash pane shows builds, review rounds, lessons and token use in one place. Install: /plugin install specclaw-dash@chan4lk (say \"no\" to never see this again)
rc=0" ]'
check "062 AC-8 Codex never gets the dash tip (mods do not run there)" '[ "$(CODEX_THREAD_ID=t sug "$S" dash 2>&1)" = "rc=0" ] && [ "$(CODEX_SANDBOX=1 sug "$S" dash 2>&1)" = "rc=0" ] && [ "$(sug "$S" dash | head -1)" != "rc=0" ]'
mkdir -p "$TMP/cache/chan4lk/specclaw-dash/0.9.8/.claude-plugin" && : > "$TMP/cache/chan4lk/specclaw-dash/0.9.8/.claude-plugin/plugin.json"
check "062 AC-8 dash in the plugin cache prints nothing" '[ "$(sug "$S" dash)" = "rc=0" ]'
mkdir -p "$TMP/co/specclaw" "$TMP/co/specclaw-dash/.claude-plugin" && : > "$TMP/co/specclaw-dash/.claude-plugin/plugin.json"
check "062 AC-8 dash beside core in a checkout prints nothing" '[ "$(PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$TMP/co/specclaw" "$BIN/specclaw-suggest" "$S" dash; echo "rc=$?")" = "rc=0" ]'
mkdir -p "$TMP/cache/chan4lk/specclaw-review/0.9.8/.claude-plugin" && : > "$TMP/cache/chan4lk/specclaw-review/0.9.8/.claude-plugin/plugin.json"
check "062 AC-8 a plugin that ships a command needs the command, not just its manifest" '[ "$(sug "$TMP/bare" review | head -1)" != "rc=0" ]'
check "062 AC-8 both status skills name the dash call" 'grep -q "specclaw-suggest .specclaw dash" "$PLUGIN_DIR/skills/status/SKILL.md" && grep -q "specclaw-suggest .specclaw dash" "$PLUGIN_DIR/references/full/status.md"'

check "AC-7 every call site names specclaw-suggest, verify no longer skips silently" '(for f in skills/verify/SKILL.md references/full/verify.md skills/status/SKILL.md references/full/status.md skills/propose/SKILL.md references/full/propose.md skills/init/SKILL.md references/full/init.md; do grep -q "specclaw-suggest" "$PLUGIN_DIR/$f" || exit 1; done) && ! grep -qiE "skip(s)? (it )?silently" "$PLUGIN_DIR/skills/verify/SKILL.md" "$PLUGIN_DIR/references/full/verify.md"'

# 063 AC-7: the dash's dismissed list and its undo.
mkdir -p "$TMP/u" && printf 'plugins:\n  dismissed: [review, bf, fleet]  # why\nnext: 1\n' > "$TMP/u/config.yaml"
check "063 AC-7 --dismissed prints one feature per line" '[ "$(sug "$TMP/u" --dismissed)" = "review
bf
fleet
rc=0" ]'
sug "$TMP/u" --undismiss bf >/dev/null
check "063 AC-7 --undismiss removes one feature, keeps the rest and the comment" 'grep -qxE "  dismissed: \[review, fleet\][[:space:]]+# why" "$TMP/u/config.yaml" && grep -qx "next: 1" "$TMP/u/config.yaml" && [ "$(sug "$TMP/u" bf | head -1)" != "rc=0" ]'
sug "$TMP/u" --undismiss review >/dev/null; sug "$TMP/u" --undismiss fleet >/dev/null; sug "$TMP/u" --undismiss fleet >/dev/null
check "063 AC-7 undoing the last one leaves an empty list; undoing again is a no-op" 'grep -qE "^  dismissed: \[\]" "$TMP/u/config.yaml" && [ "$(sug "$TMP/u" --dismissed)" = "rc=0" ]'
# Undo failures exit 1 (the dash shows the exit code) and leave the config as it was.
for row in none:- rodir:555 unreadable:000 rofile:444; do
  name="${row%%:*}"; mode="${row#*:}"; d="$TMP/uf-$name"
  if [ "$mode" != - ]; then
    mkdir -p "$d" && printf 'plugins:\n  dismissed: [review]\n' > "$d/config.yaml" && cp "$d/config.yaml" "$d.orig"
    if [ "$name" = rodir ]; then chmod "$mode" "$d"; else chmod "$mode" "$d/config.yaml"; fi
  fi
  err="$(sug "$d" --undismiss review 2>&1)"
  chmod 755 "$d" 2>/dev/null; chmod 644 "$d/config.yaml" 2>/dev/null
  check "063 AC-7 --undismiss failure ($name) says so, exit 1, config unchanged" 'grep -q "could not record undo of dismissal of '"'"'review'"'"'" <<<"$err" && grep -q "rc=1" <<<"$err" && { [ "$mode" = - ] || cmp -s "$d/config.yaml" "$d.orig"; }'
done

echo
[ "$FAILS" -eq 0 ] && echo "All suggest tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
