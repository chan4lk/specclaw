#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"

FAKE_PR=1 run_entry; ok_rc=$?; ok_status="$(cat "$TMP/status/exit")"; ok_calls="$(cat "$CALLS")"
AGENT_RC=5 run_entry; bad_rc=$?; bad_status="$(cat "$TMP/status/exit")"; bad_calls="$(cat "$CALLS")"
CLONE_FAIL=1 REAL_AZDO="$FLEET_ROOT/../specclaw-sync/bin/specclaw-azdo-issue" AZDO_ORG=o AZDO_PROJECT=p run_entry; clone_rc=$?
clone_patch="$(grep -- "-X PATCH" "$TMP/curl.log" 2>/dev/null)"; clone_status="$(cat "$TMP/status/exit")"; clone_calls="$(cat "$CALLS")"
clone_wi="$(cat "$TMP/work/fallback/.specclaw/changes/049-x/status.md" 2>/dev/null)"
clone_cfg="$(cat "$TMP/work/fallback/.specclaw/config.yaml" 2>/dev/null)"
NOT_ANCESTOR=1 run_entry; stale_rc=$?; stale_status="$(cat "$TMP/status/exit")"; stale_calls="$(cat "$CALLS")"
recheck_ok=1
for st in "NOT_APPROVED" MISSING '{"phases":{' '[]' '{"phases":{}}' '{"phases":{"proposal":{"status":"approved "}}}' '{"phases":{"proposal":{"status":"none"}}}'; do
  if [[ "$st" == NOT_APPROVED ]]; then NOT_APPROVED=1 run_entry; else STATE_OVERRIDE="$st" run_entry; fi
  [[ "$(cat "$TMP/status/exit")" == 2 ]] && grep -q "exit=not-approved-at-ref" "$CALLS" && ! grep -q "state=running" "$CALLS" || recheck_ok=0
done
AGENT_SLEEP=20 FLEET_AGENT_TIMEOUT=8 run_entry; late_rc=$?; late_status="$(cat "$TMP/status/exit")"; late_calls="$(cat "$CALLS")"

repo_ok=1
while IFS='|' read -r preset url want; do
  rm -f "$TMP/azdorepo"; url="${url:-https://dev.azure.com/o/p/_git/r}"; [[ "$url" == none ]] && url=""
  if [[ -z "$preset" ]]; then ENTRY_REPO_URL="$url" run_entry; else AZDO_REPO="$preset" ENTRY_REPO_URL="$url" run_entry; fi
  if [[ "$want" == WARN ]]; then grep -q "WARN: AZDO_REPO is empty" "$TMP/out" || { repo_ok=0; echo "  [AZDO_REPO |$url] no warning"; }
  else [[ "$(cat "$TMP/azdorepo" 2>/dev/null)" == "$want" ]] || { repo_ok=0; echo "  [AZDO_REPO $preset|$url] got $(cat "$TMP/azdorepo" 2>/dev/null)"; }; fi
done <<'EOF'
||r
preset||preset
other||other
|none|WARN
|https://dev.azure.com/o/p/_git//|WARN
|https://dev.azure.com/o/p/_git/r/|r
|https://dev.azure.com/o/p/_git/r.git|r
|https://dev.azure.com/o/p/_git/r.git/|r
EOF
azdo_repo_set() { (( repo_ok == 1 )); }

keys_unset() { [[ ! -s "$TMP/leaked" ]]; }
no_token_in_url() { ! grep -q "pat-secret" <<<"$ok_calls"; }
pr_open_flow() {
  (( ok_rc == 0 )) && [[ "$ok_status" == 0 ]] && grep -q "state=running" <<<"$ok_calls" && grep -q "state=pr_open exit=0 branch=specclaw/049-x pr=https://pr/1 draft=false" <<<"$ok_calls"
}
failed_flow() { (( bad_rc == 0 )) && [[ "$bad_status" == 5 ]] && grep -q "state=pr_open exit=5 .*draft=true" <<<"$bad_calls"; }

clone_failure_recorded() {
  (( clone_rc == 0 )) && [[ "$clone_status" == 2 ]] && grep -q "fallback/.specclaw 049-x state=failed exit=clone-failed" <<<"$clone_calls" \
    && grep -q "#42" <<<"$clone_wi" && grep -q "failed: Failed" <<<"$clone_cfg" \
    && grep -q 'workitems/42.*"path": "/fields/System.State", "value": "Failed"' <<<"$clone_patch"
}
commit_pinned() {
  grep -q "state=running built_commit=deadbeef" <<<"$ok_calls" && (( stale_rc == 0 )) && [[ "$stale_status" == 2 ]] \
    && grep -q "exit=commit-not-on-ref dispatched_commit=abc123" <<<"$stale_calls" && ! grep -q "state=running" <<<"$stale_calls"
}
approval_rechecked() { (( recheck_ok == 1 )); }
deadline_leaves_room() { (( late_rc == 0 )) && [[ "$late_status" == 143 ]] && grep -q "exit=deadline branch=" <<<"$late_calls"; }

check "R056 AC-1 the agent sees AZDO_REPO from the cloned repo URL (a trailing slash or .git is stripped, an empty name warns); a preset AZDO_REPO wins" azdo_repo_set
check "AC7 API-key variables unset before the agent runs" keys_unset
check "AC7 clone URL and git args carry no token" no_token_in_url
check "AC7 Running then PR Open when a PR is recorded" pr_open_flow
check "AC7 agent failure: exits 0, keeps the real status, opens a draft PR" failed_flow
check "AC7 clone failure carries the state mapping, so Failed is a real state change" clone_failure_recorded
check "AC7 cloned commit recorded; a ref missing the dispatched commit fails before the agent runs" commit_pinned
check "AC7 in-pod deadline stops the agent, records it, exits 0 so write-back runs" deadline_leaves_room
check "AC7 proposal not approved at the ref (draft, missing, truncated, array, no proposal, padded, none): Failed, agent never runs" approval_rechecked
finish
