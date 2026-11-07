#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
ENTRY="$FLEET_ROOT/image/entrypoint.sh"
stub specclaw-azdo-issue 'exit 0'
stub git '[[ "$1" == clone ]] || exit 0
[[ -n "${CLONE_FAIL:-}" ]] && exit 128
dest="${*: -1}"; mkdir -p "$dest/.specclaw/changes/049-x"
[[ -n "${FAKE_PR:-}" ]] && echo "{\"phases\":{\"pr\":{\"url\":\"https://pr/1\"}}}" > "$dest/.specclaw/changes/049-x/state.json"
exit 0'
stub claude 'env | grep -E "^(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|CODEX_API_KEY)=" >> "$TMP/leaked"
[[ "$CLAUDE_CODE_OAUTH_TOKEN" == oat-token ]] || echo "bad token" >> "$TMP/leaked"
sleep "${AGENT_SLEEP:-0}"
exit "${AGENT_RC:-0}"'
export TMP

run_entry() {
  rm -rf "${TMP:?}/status" "${TMP:?}/work" "${TMP:?}/home"
  mkdir -p "$TMP/status" "$TMP/work" "$TMP/home" "$TMP/seed"
  : > "$CALLS"
  printf 'oat-token' > "$TMP/cred"
  env FLEET_STATUS_DIR="$TMP/status" FLEET_WORK="$TMP/work" FLEET_CRED="$TMP/cred" FLEET_SEED="$TMP/seed" \
    FLEET_WORK_ITEM=42 HOME="$TMP/home" FLEET_AGENT=claude FLEET_CHANGE=049-x FLEET_REF=main AZDO_TOKEN=pat-secret \
    FLEET_REPO_URL=https://dev.azure.com/o/p/_git/r ANTHROPIC_API_KEY=k ANTHROPIC_AUTH_TOKEN=k OPENAI_API_KEY=k CODEX_API_KEY=k \
    bash "$ENTRY" > "$TMP/out" 2>&1
}

FAKE_PR=1 run_entry; ok_rc=$?; ok_status="$(cat "$TMP/status/exit")"; ok_calls="$(cat "$CALLS")"
AGENT_RC=5 run_entry; bad_rc=$?; bad_status="$(cat "$TMP/status/exit")"; bad_calls="$(cat "$CALLS")"
CLONE_FAIL=1 run_entry; clone_rc=$?; clone_status="$(cat "$TMP/status/exit")"; clone_calls="$(cat "$CALLS")"
clone_wi="$(cat "$TMP/work/fallback/.specclaw/changes/049-x/status.md" 2>/dev/null)"
AGENT_SLEEP=5 FLEET_AGENT_TIMEOUT=1 run_entry; late_rc=$?; late_status="$(cat "$TMP/status/exit")"; late_calls="$(cat "$CALLS")"

keys_unset() { [[ ! -s "$TMP/leaked" ]]; }
no_token_in_url() { ! grep -q "pat-secret" <<<"$ok_calls"; }
pr_open_flow() {
  (( ok_rc == 0 )) && [[ "$ok_status" == 0 ]] && grep -q "state=running" <<<"$ok_calls" && grep -q "state=pr_open" <<<"$ok_calls"
}
failed_flow() { (( bad_rc == 0 )) && [[ "$bad_status" == 5 ]] && grep -q "state=failed exit=5" <<<"$bad_calls"; }

clone_failure_recorded() {
  (( clone_rc == 0 )) && [[ "$clone_status" == 2 ]] && grep -q "fallback/.specclaw 049-x state=failed exit=clone-failed" <<<"$clone_calls" \
    && grep -q "#42" <<<"$clone_wi"
}
deadline_leaves_room() { (( late_rc == 0 )) && [[ "$late_status" == 143 ]] && grep -q "state=failed exit=deadline" <<<"$late_calls"; }

check "AC7 API-key variables unset before the agent runs" keys_unset
check "AC7 clone URL and git args carry no token" no_token_in_url
check "AC7 Running then PR Open when a PR is recorded" pr_open_flow
check "AC7 agent failure: exits 0, records Failed and the real status" failed_flow
check "AC7 clone failure still marks the work item Failed" clone_failure_recorded
check "AC7 in-pod deadline stops the agent, records it, exits 0 so write-back runs" deadline_leaves_room
finish
