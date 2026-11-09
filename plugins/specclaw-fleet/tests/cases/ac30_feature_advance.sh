#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export TMP SPECCLAW_DIR="$TMP/repo/.specclaw" FLEET_AZDO_ISSUE="$TMP/stub/specclaw-azdo-issue" AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t
stub specclaw-azdo-issue 'case "$1" in
  show) [[ "$3" == 009-u ]] && { case "${UNREAD:-html}" in html) echo "<html>" ;; fail) exit 1 ;; array) echo "[]" ;; esac; exit 0; } ;;&
  show) [[ "$3" == 006-f ]] && echo "{\"fields\":{\"System.Tags\":\"fleet:auto; fleet:conflict-retried\"}}" || echo "{\"fields\":{\"System.Tags\":\"fleet:auto\"}}" ;;
  create) printf "**Azure Boards Work Item:** [#300](https://x)\n" >> "$2/features/$3/status.md" ;;
esac; exit 0'
advance() {
  printf '%s' "$1" > "$TMP/states.json"; : > "$TMP/dispatch.log"; : > "$CALLS"
  env FLEET_TRUSTED_BRANCH="${2:-}" DISPATCH_RC="${3:-0}" UNREAD="${UNREAD:-html}" bash -c '
    FLEET_ROOT="$1"; SPECCLAW_DIR="$2"; FLEET_TMPDIR="$(mktemp -d)"; for l in "$1"/lib/*.sh; do source "$l"; done
    feature_states() { cat "$TMP/states.json"; }
    fleet_dispatch() { echo "dispatch $* ref=$FLEET_REF merge=${FLEET_MERGE_REF:-} mode=${FLEET_MODE:-} target=${FLEET_PR_TARGET:-}" >> "$TMP/dispatch.log"; return "${DISPATCH_RC:-0}"; }
    record_run() { echo "record $*" >> "$TMP/dispatch.log"; }
    [[ -z "$FLEET_TRUSTED_BRANCH" ]] && unset FLEET_TRUSTED_BRANCH
    feature_advance cat' _ "$FLEET_ROOT" "$SPECCLAW_DIR" > "$TMP/out" 2>&1
}
S() { local o="[" sep=""; for p in "$@"; do o+="$sep{\"change\":\"${p%%=*}\",\"state\":\"${p#*=}\"}"; sep=","; done; echo "$o]"; }
advance "$(S 002-a=merged 003-b=ready 004-c=waiting 005-d=failed 006-f=conflict 007-e=conflict 008-g=not-opted-in)"; mixed_rc=$?; log="$(cat "$TMP/dispatch.log")"; calls="$(cat "$CALLS")"
mixed() {
  (( mixed_rc == 0 )) && [[ $(grep -c '^dispatch' <<<"$log") == 2 ]] \
    && grep -qx "dispatch 003-b ref=feature/cat merge= mode= target=" <<<"$log" \
    && grep -qx "dispatch 007-e --force ref=feature/cat merge=feature/cat mode= target=" <<<"$log" \
    && grep -q "record 006-f state=failed exit=merge-conflict" <<<"$log" && grep -q "azdo-issue tag .* 006-f fleet:refused" <<<"$calls" \
    && grep -q "azdo-issue tag .* 007-e fleet:conflict-retried" <<<"$calls" && ! grep -q "mode=integrate" <<<"$log"
}
check "R050 AC-4 advance dispatches only ready members on feature/<m>; a failed member blocks only its dependents; a conflict is retried once with the merge ref, then marked failed" mixed
advance "$(S 002-a=merged 003-b=merged)"; all_log="$(cat "$TMP/dispatch.log")"
advance "$(S 002-a=merged 003-b=merged)" release; rel_log="$(cat "$TMP/dispatch.log")"
advance "$(S 002-a=merged 003-b=merged)" "" 3; again_rc=$?
integration_once() {
  [[ "$all_log" == "dispatch cat ref=feature/cat merge= mode=integrate target=main" && "$rel_log" == *"target=release" ]] && (( again_rc == 0 ))
}
check "R050 AC-4 when every member is merged, advance dispatches the feature item once in integrate mode into the trusted branch; a repeat (already handled) is a no-op" integration_once
advance "$(S 003-b=ready)" "" 1; err_rc=$?
errors_fail() { (( err_rc != 0 )) && grep -q '"errors":1' "$TMP/out"; }
check "R050 AC-4 a dispatch error makes advance fail and counts it" errors_fail
unread_ok=1
for u in html fail array; do
  UNREAD=$u advance "$(S 009-u=conflict)"; rc=$?
  (( rc != 0 )) && [[ ! -s "$TMP/dispatch.log" ]] && ! grep -q "azdo-issue tag" "$CALLS" || { unread_ok=0; echo "  unread $u: rc=$rc"; }
done
unread_no_retry() { (( unread_ok == 1 )); }
check "R050 an unreadable work item in conflict (html, non-zero exit, non-object JSON) is an error: no retry tag, no dispatch" unread_no_retry
rm -rf "$TMP/repo"; mkdir -p "$SPECCLAW_DIR/changes/002-a" "$SPECCLAW_DIR/changes/003-b"
printf '**Feature:** cat\n' > "$SPECCLAW_DIR/changes/002-a/proposal.md"; printf '**Feature:** cat\n**Depends on:** 002-a\n' > "$SPECCLAW_DIR/changes/003-b/proposal.md"
(cd "$TMP/repo" && "$FLEET" feature init cat) > "$TMP/out" 2>&1; init_rc=$?
(cd "$TMP/repo" && "$FLEET" feature init nobody) > "$TMP/out2" 2>&1; empty_rc=$?
init_ok() {
  (( init_rc == 0 && empty_rc != 0 )) && jq -e '.kind == "feature" and .phases.proposal.status == "approved"' "$SPECCLAW_DIR/features/cat/state.json" >/dev/null \
    && grep -q "wave 2: 003-b" "$SPECCLAW_DIR/features/cat/proposal.md" && grep -q "#300" "$SPECCLAW_DIR/features/cat/status.md" && grep -q "has no members" "$TMP/out2"
}
check "R050 AC-2 feature init writes an approved feature record with its waves and a work item; an empty feature is refused" init_ok
git -C "$TMP/repo" init -q && git init -q --bare "$TMP/remote.git" && git -C "$TMP/repo" remote add local "$TMP/remote.git"
git -C "$TMP/repo" add -A && git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q -m f && git -C "$TMP/repo" push -q local HEAD:main
stub az 'case "$*" in "pipelines run"*) echo "$*" >> "$TMP/az.log"; echo 5150 ;; esac'
start() { (cd "$TMP/repo" && FLEET_REMOTE=local FLEET_REF=main "$FLEET" feature start "$1") > "$TMP/out" 2>&1; }
start cat; first_rc=$?; first="$(cat "$TMP/out")"; br1="$(git -C "$TMP/remote.git" rev-parse -q --verify refs/heads/feature/cat)"
git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m newer && git -C "$TMP/repo" push -q local HEAD:main
start cat; br2="$(git -C "$TMP/remote.git" rev-parse -q --verify refs/heads/feature/cat)"
start nofeature; missing_rc=$?
start_ok() {
  (( first_rc == 0 && missing_rc != 0 )) && [[ -n "$br1" && "$br1" == "$br2" ]] && jq -e '.run == "5150" and .branch == "feature/cat"' <<<"${first##*$'\n'}" >/dev/null \
    && grep -q -- "--branch feature/cat" "$TMP/az.log" && grep -q "feature nofeature is not on local/main" "$TMP/out"
}
check "R050 AC-6 feature start creates feature/<m> only when missing, then queues the pipeline on it; a feature not pushed is refused" start_ok
finish
