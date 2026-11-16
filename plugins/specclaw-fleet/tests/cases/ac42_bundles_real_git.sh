#!/usr/bin/env bash
set -uo pipefail
# Real git (no stub) for the bundle functions: save, verify, ancestor checks, fetch, fast-forward, delete only when pushed.
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export FLEET_BUNDLES=on FLEET_BUNDLE_DIR="$TMP/bundles" FLEET_CHANGE=049-x FLEET_PUSH_ATTEMPTS=1 FLEET_PUSH_PAUSES=0
# shellcheck disable=SC2034 # STATE is read by change_branch
STATUS="$TMP/status" SEED="$TMP/seed" HOME="$TMP/home" REPO="$TMP/repo" STATE="$TMP/none.json" ORIGIN="$TMP/origin.git"
mkdir -p "$STATUS" "$SEED" "$HOME" "$FLEET_BUNDLE_DIR"
# shellcheck source=../../image/tracker.sh
source "$FLEET_ROOT/image/tracker.sh"
# shellcheck source=../../image/workspace.sh
source "$FLEET_ROOT/image/workspace.sh"
B="$FLEET_BUNDLE_DIR" BR=specclaw/049-x
g() { git -C "$REPO" "$@"; }
commit() { g commit -q --allow-empty -m "$1" && g rev-parse HEAD; }
fresh_clone() { rm -rf "$REPO"; git clone -q "$ORIGIN" "$REPO" && prepare_workspace 2>"$TMP/out"; }
tip() { git -C "$ORIGIN" rev-parse "refs/heads/$BR" 2>/dev/null; }
pushed_ok() { push_change_branch >/dev/null 2>>"$TMP/out"; }

git init -q --bare -b main "$ORIGIN"; git clone -q "$ORIGIN" "$REPO" 2>/dev/null; commit c0 >/dev/null; g push -q origin main

# Run 1 pushes c1, adds c2, then its push fails: the bundle holds c0..c2.
fresh_clone; g checkout -q -b "$BR"; c1="$(commit c1)"; pushed_ok; c2="$(commit c2)"
g remote set-url --push origin "$TMP/gone"; pushed_ok; r1_rc=$?; r1_save="$(save_bundle)"; g remote set-url --push origin "$ORIGIN"
r1_verify="$(g bundle verify "$B/work.bundle" >/dev/null 2>&1 && echo ok)"; r1_base="$(cat "$B/work.base")"
# Run 2: the remote branch is at c1, the bundle at c2: fast-forward, push, then the bundle goes.
fresh_clone; r2_out="$(cat "$TMP/out")"; r2_head="$(g rev-parse HEAD)"; pushed_ok; r2_tip="$(tip)"; r2_left="$(ls "$B")"
# Diverged: a bundle at c3 on c1, while the remote moved to c4 on c2. The remote wins, the bundle stays after a push.
fresh_clone; g checkout -q -B "$BR" "$c1"; c3="$(commit c3)"; BUNDLE_BASE="$(g rev-parse origin/main)" save_bundle >/dev/null
fresh_clone; c4="$(commit c4)"; pushed_ok
fresh_clone; dv_out="$(cat "$TMP/out")"; dv_head="$(g rev-parse HEAD)"; : > "$TMP/out"; pushed_ok; dv_push="$(cat "$TMP/out")"; dv_left="$(ls "$B" | tr '\n' ' ')"
# Still diverged, and this run's own push fails: the diverged bundle is set aside, never overwritten.
c5="$(commit c5)"; ds_save="$(save_bundle 2>/dev/null)"; ds_kept="$(g bundle list-heads "$B"/kept-*.bundle 2>/dev/null | cut -d' ' -f1)"
ds_new="$(g bundle list-heads "$B/work.bundle" | cut -d' ' -f1)"; ds_bases="$(cat "$B"/kept-*.base 2>/dev/null)"; rm -f "$B"/kept-*
# Table: what a failed push does to an older bundle (the branch is at c5, on c4 on c2).
KEPT='saved,kept=kept-1'
old() { g branch -q -f old_in "$c2"; g branch -q -f old_out "$c3"; echo "$c0" > "$B/work.base"; g bundle create -q "$B/work.bundle" "$@" ^origin/main; }
# Modes: rw; ro folder; kept-1.bundle or only kept-1.base taken; bundle create fails; the base cannot move.
REAL_GIT="$(command -v git)"; mkdir -p "$TMP/shim"; printf '#!/bin/sh\n[ "$3 $4" = "bundle create" ] && exit 1\nexec "%s" "$@"\n' "$REAL_GIT" > "$TMP/shim/git"; chmod +x "$TMP/shim/git"
no_create() { PATH="$TMP/shim:$PATH" save_bundle; }
no_base_move() { mv() { [[ "${*: -1}" == */kept-*.base ]] && return 1; command mv "$@"; }; save_bundle; }
aside_row() {
  local out n keep="" fn=save_bundle before name; rm -rf "${B:?}"/*; "old_$1"; before="$(g bundle list-heads "$B/work.bundle" 2>/dev/null)"
  case "$4" in ro) chmod a-w "$B" ;; taken) echo first > "$B/kept-1.bundle" ;; taken_base) echo first > "$B/kept-1.base" ;; no_create) fn=no_create ;; no_base) fn=no_base_move ;; esac
  out="$("$fn" 2>/dev/null)"; chmod u+w "$B"; n="$(find "$B" -name 'kept-*.bundle' | wc -l | tr -d ' ')"
  [[ "$4" == ro ]] && keep="$(g bundle list-heads "$B/work.bundle" | cut -d' ' -f1)"
  [[ "$4" != taken* || "$(cat "$B"/kept-1.*)" == first ]] || { echo "row $1 $4: kept-1 was replaced"; return 1; }
  [[ "$out" =~ ^$2$ && "$n" == "$3" && ( "$4" != ro || "$keep" == "$c3" ) ]] || { echo "row $1 $4: out=$out kept=$n"; return 1; }
  [[ "$4" != no_create ]] || [[ -z "$(find "$B" -name 'work.bundle*')" ]] || { echo "row $1 $4: a work.bundle was left"; return 1; }
  [[ "$out" == *kept=* ]] || return 0
  name="${out#*kept=}" name="${name%%,*}"
  [[ "$(g bundle list-heads "$B/$name.bundle" 2>/dev/null)" == "$before" ]] || { echo "row $1 $4: $name.bundle is not the old bundle"; return 1; }
  [[ "$4" == no_base && ! -e "$B/$name.base" ]] || [[ "$(cat "$B/$name.base" 2>/dev/null)" == "$c0" ]] || { echo "row $1 $4: $name.base"; return 1; }
}
old_contained() { old old_in; }
old_diverged() { old old_out; }
old_two_heads() { old old_in old_out; }
old_junk() { echo junk > "$B/work.bundle"; }
c0="$(g rev-parse origin/main)"; aside_rows=0
while read -r row want kept mode; do aside_row "$row" "$want" "$kept" "$mode" || aside_rows=1; done <<ROWS
contained saved 0 rw
diverged $KEPT 1 rw
two_heads $KEPT 1 rw
junk saved 0 rw
diverged saved,kept=kept-2 2 taken
diverged saved,kept=kept-2 1 taken_base
diverged none,kept=kept-1 1 no_create
diverged saved,kept=kept-1,kept_base=none 1 no_base
ROWS
ro_row=skipped; [[ "$(id -u)" == 0 ]] || { ro_row=fail; aside_row diverged none 0 ro && ro_row=ok; }
# Behind: the bundle tip (c3's branch rebuilt as c2) is already in the remote; no warning, and the push deletes it.
rm -f "$B"/work.*; g checkout -q -B tmp "$c2"; g branch -q -f "$BR" "$c2"; BUNDLE_BASE="$(g rev-parse origin/main)" save_bundle >/dev/null
fresh_clone; bh_out="$(cat "$TMP/out")"; bh_head="$(g rev-parse HEAD)"; pushed_ok; bh_left="$(ls "$B")"
# A base that is a commit id but not in this history, and a file that is not a bundle.
rm -f "$B"/work.*; g checkout -q -B "$BR" "$c4"; BUNDLE_BASE="$(g rev-parse origin/main)" save_bundle >/dev/null; printf '%040d\n' 7 > "$B/work.base"
fresh_clone; na_out="$(cat "$TMP/out")"; na_head="$(g rev-parse HEAD)"
echo junk > "$B/work.bundle"; pushed_ok; junk_left="$(ls "$B")"
# A spent delivery budget pushes nothing and says why.
commit c6 >/dev/null; rm -f "$STATUS/push-error"; DELIVER_BY=$SECONDS pushed_ok; sk_rc=$?; sk_err="$(cat "$STATUS/push-error")"; sk_tip="$(tip)"

saves() { (( r1_rc != 0 )) && [[ "$r1_save" == saved && "$r1_verify" == ok && "$r1_base" == "$(git -C "$ORIGIN" rev-parse main)" ]]; }
fast_forwards() {
  grep -q "resuming existing change branch $BR" <<<"$r2_out" && grep -q "resuming from saved bundle" <<<"$r2_out" \
    && [[ "$r2_head" == "$c2" && "$r2_tip" == "$c2" && -z "$r2_left" ]]
}
diverged() {
  grep -q "WARNING: saved bundle $B/work.bundle has diverged" <<<"$dv_out" && [[ "$dv_head" == "$c4" && "$dv_left" == "work.base work.bundle " ]] \
    && grep -q "WARNING: kept $B/work.bundle" <<<"$dv_push" && git -C "$ORIGIN" merge-base --is-ancestor "$c2" "$c4" && [[ -n "$c3" ]]
}
set_aside() { [[ "$ds_save" =~ ^$KEPT$ && "$ds_kept" == "$c3" && "$ds_new" == "$c5" && -n "$ds_bases" ]]; }
aside_table() { [[ "$aside_rows" == 0 ]]; }
test_ro() { [[ "$ro_row" == ok ]]; }
behind() { [[ "$bh_head" == "$c4" && -z "$bh_left" ]] && ! grep -q "saved bundle" <<<"$bh_out"; }
not_ancestor() { grep -q "is not a commit id that is an ancestor" <<<"$na_out" && [[ "$na_head" == "$c4" && -z "$junk_left" ]]; }

check "real git: a failed push saves a bundle that verifies, with the clone's base" saves
check "real git: remote branch behind the bundle fast-forwards to it, and the good push deletes the bundle" fast_forwards
check "real git: a bundle that diverged from the remote branch is warned about and kept after the push" diverged
check "real git: a failed push never overwrites a bundle holding commits the branch lacks; it is set aside" set_aside
check "real git: older bundle table: contained or unreadable is replaced; diverged or several heads is set aside under the recorded name; a taken kept name (bundle or base) is never replaced; a failed create records none,kept; a base that cannot move is reported" aside_table
if [[ "$ro_row" == skipped ]]; then echo "SKIP: real git: a set-aside that cannot move the bundle saves nothing (running as root, the folder stays writable)"
else check "real git: a set-aside that cannot move the bundle saves nothing and leaves it" test_ro; fi
check "real git: a bundle already in the remote branch resumes nothing and is deleted after the push" behind
spent() { (( sk_rc != 0 )) && [[ "$sk_err" == "push skipped: delivery budget spent" && "$sk_tip" == "$c4" ]]; }
check "real git: a spent delivery budget makes no push attempt and records why" spent
check "real git: a base outside this history is ignored; a file that is not a bundle is deleted after a good push" not_ancestor
finish
