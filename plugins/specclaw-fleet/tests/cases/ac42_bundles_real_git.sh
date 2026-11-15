#!/usr/bin/env bash
set -uo pipefail
# Real git (no stub) for the bundle functions: save, verify, ancestor checks, fetch, fast-forward, delete only when pushed.
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export FLEET_BUNDLE_DIR="$TMP/bundles" FLEET_CHANGE=049-x FLEET_PUSH_ATTEMPTS=1 FLEET_PUSH_PAUSES=0
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
# Behind: the bundle tip (c3's branch rebuilt as c2) is already in the remote; no warning, and the push deletes it.
rm -f "$B"/work.*; g checkout -q -B tmp "$c2"; g branch -q -f "$BR" "$c2"; BUNDLE_BASE="$(g rev-parse origin/main)" save_bundle >/dev/null
fresh_clone; bh_out="$(cat "$TMP/out")"; bh_head="$(g rev-parse HEAD)"; pushed_ok; bh_left="$(ls "$B")"
# A base that is a commit id but not in this history, and a file that is not a bundle.
rm -f "$B"/work.*; g checkout -q -B "$BR" "$c4"; BUNDLE_BASE="$(g rev-parse origin/main)" save_bundle >/dev/null; printf '%040d\n' 7 > "$B/work.base"
fresh_clone; na_out="$(cat "$TMP/out")"; na_head="$(g rev-parse HEAD)"
echo junk > "$B/work.bundle"; pushed_ok; junk_left="$(ls "$B")"

saves() { (( r1_rc != 0 )) && [[ "$r1_save" == saved && "$r1_verify" == ok && "$r1_base" == "$(git -C "$ORIGIN" rev-parse main)" ]]; }
fast_forwards() {
  grep -q "resuming existing change branch $BR" <<<"$r2_out" && grep -q "resuming from saved bundle" <<<"$r2_out" \
    && [[ "$r2_head" == "$c2" && "$r2_tip" == "$c2" && -z "$r2_left" ]]
}
diverged() {
  grep -q "WARNING: saved bundle $B/work.bundle has diverged" <<<"$dv_out" && [[ "$dv_head" == "$c4" && "$dv_left" == "work.base work.bundle " ]] \
    && grep -q "WARNING: kept $B/work.bundle" <<<"$dv_push" && git -C "$ORIGIN" merge-base --is-ancestor "$c2" "$c4" && [[ -n "$c3" ]]
}
set_aside() { [[ "$ds_save" == saved && "$ds_kept" == "$c3" && "$ds_new" == "$c5" && -n "$ds_bases" ]]; }
behind() { [[ "$bh_head" == "$c4" && -z "$bh_left" ]] && ! grep -q "saved bundle" <<<"$bh_out"; }
not_ancestor() { grep -q "is not a commit id that is an ancestor" <<<"$na_out" && [[ "$na_head" == "$c4" && -z "$junk_left" ]]; }

check "real git: a failed push saves a bundle that verifies, with the clone's base" saves
check "real git: remote branch behind the bundle fast-forwards to it, and the good push deletes the bundle" fast_forwards
check "real git: a bundle that diverged from the remote branch is warned about and kept after the push" diverged
check "real git: a failed push never overwrites a bundle holding commits the branch lacks; it is set aside" set_aside
check "real git: a bundle already in the remote branch resumes nothing and is deleted after the push" behind
check "real git: a base outside this history is ignored; a file that is not a bundle is deleted after a good push" not_ancestor
finish
