#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
stub specclaw-fleet 'exit 0'
export AGENT_TEMPDIRECTORY="$TMP" SYSTEM_COLLECTIONURI=https://dev.azure.com/o/
sed -n '/inlineScript: |/,/^    env:/p' "$FLEET_ROOT/pipelines/dispatch.yml" | sed '1d;$d;s/^        //' \
  | sed 's/\${{ parameters.vault }}/kv/' > "$TMP/step.sh"

repo_with() {
  rm -rf "$TMP/r" && mkdir -p "$TMP/r/.specclaw/changes/049-x" && cd "$TMP/r" && git init -q
  git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
  local state
  for state in "$@"; do
    printf '%s' "$state" > .specclaw/changes/049-x/state.json
    git add -A && git -c user.name=t -c user.email=t@t commit -q -m step
  done
  : > "$CALLS"
}
run_step() { bash "$TMP/step.sh" > "$TMP/out" 2>&1; }
APPROVED='{"phases":{"proposal":{"status":"approved"}}}'

repo_with "$APPROVED"; run_step; flip_rc=$?; flip_calls="$(cat "$CALLS")"
repo_with "$APPROVED"; git -c user.name=t -c user.email=t@t commit -q --allow-empty -m noop; run_step; same_calls="$(cat "$CALLS")"
repo_with '{"phases":{"proposal":{"status":"draft"}}}' '{"phases":{'; run_step; bad_json_rc=$?; bad_json_out="$(cat "$TMP/out")"
repo_with; git checkout -q --orphan solo && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m solo; run_step; no_parent_rc=$?

dispatches_flip() { (( flip_rc == 0 )) && grep -q "specclaw-fleet dispatch 049-x --vault kv" <<<"$flip_calls"; }
ignores_no_flip() { [[ -z "$same_calls" ]]; }
fails_unreadable() { (( bad_json_rc != 0 )) && grep -q "could not read proposal status" <<<"$bad_json_out"; }
fails_no_diff() { (( no_parent_rc != 0 )); }

check "FR10 dispatches a change whose proposal flipped to approved" dispatches_flip
check "FR10 no dispatch when nothing flipped" ignores_no_flip
check "FR10 an unreadable state.json fails the step, never reads as not approved" fails_unreadable
check "FR10 a failed git diff (no parent commit) fails the step" fails_no_diff
finish
