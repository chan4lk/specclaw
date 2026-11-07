#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster

refused() { (( rc != 0 )) && nothing_applied; }
refused_4() { (( rc == 4 )) && nothing_applied && marked_failed; }
refused_and_failed() { refused_4; }
skipped_silently() { (( rc == 3 )) && nothing_applied && ! grep -qE "specclaw-azdo-issue (fields|tag|claim)" "$CALLS"; }
failed_unregistered() { refused_and_failed && grep -q "no registered claude credential" "$CALLS"; }
failed_vault() { refused_and_failed && grep -q "could not read Key Vault" "$CALLS"; }

reset_env; echo '{"phases":{"proposal":{"status":"draft"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"
dispatch; rc=$?; check "AC4a unapproved proposal refused" refused

reset_env; : > "$SPECCLAW_DIR/changes/$CHANGE/status.md"
dispatch; rc=$?; check "AC4b no work item refused" refused

reset_env; WI_JSON='{"fields":{"System.Tags":"fleet:auto"}}' dispatch; rc=$?
check "AC4c no assignee refused and marked Failed" refused_and_failed

for tags in "fleet:autox" "specclaw" "auto; fleet"; do
  reset_env; WI_JSON="{\"fields\":{\"System.AssignedTo\":{\"uniqueName\":\"a@c.com\"},\"System.Tags\":\"$tags\"}}" \
    BUILD_REQUESTEDFOREMAIL=other@c.com dispatch; rc=$?
  check "AC4d not opted in (tags '$tags'): exit 3, nothing written" skipped_silently
done

for who in mallory@contoso.com ""; do
  reset_env; WI_UPDATES="{\"value\":[{\"revisedBy\":{\"uniqueName\":\"$who\"},\"fields\":{\"System.Tags\":{\"oldValue\":\"\",\"newValue\":\"fleet:auto\"}}}]}" \
    dispatch; rc=$?
  check "AC4d fleet:auto added by '${who:-unknown}', not the assignee, refused" refused_and_failed
done
accepted() { (( rc == 0 )); }
READD='{"value":[{"revisedBy":{"uniqueName":"alice@contoso.com"},"fields":{"System.Tags":{"oldValue":"","newValue":"fleet:auto"}}},{"revisedBy":{"uniqueName":"alice@contoso.com"},"fields":{"System.Tags":{"oldValue":"fleet:auto","newValue":""}}},{"revisedBy":{"uniqueName":"mallory@contoso.com"},"fields":{"System.Tags":{"oldValue":"","newValue":"fleet:auto"}}}]}'
for updates in "$READD" '{"value":[]}' FAIL; do
  reset_env; WI_UPDATES="$updates" dispatch; rc=$?
  check "AC4d tag without an assignee add event (${updates:0:12}…) refused" refused_and_failed
done
reset_env; WI_JSON='{"fields":{"System.AssignedTo":{"uniqueName":"Alice@Contoso.com"},"System.Tags":"specclaw"}}' \
  BUILD_REQUESTEDFOREMAIL=alice@contoso.com dispatch; rc=$?
check "AC4d triggering the pipeline is not consent: no tag means a silent skip" skipped_silently
for tag in Fleet:Auto FLEET:AUTO " fleet:auto "; do
  reset_env; WI_JSON="{\"fields\":{\"System.AssignedTo\":{\"uniqueName\":\"Alice@Contoso.com\"},\"System.Tags\":\"x;$tag\"}}" dispatch; rc=$?
  check "AC4d tag '$tag' added by the assignee is consent (case-insensitive)" accepted
done

reset_env; echo __unset__ > "$KV/claude-token-$H"
dispatch; rc=$?; check "AC4e placeholder credential refused as unregistered" failed_unregistered
reset_env; rm "$KV/claude-token-$H"
dispatch; rc=$?; check "AC4e missing credential refused as unregistered" failed_unregistered
reset_env; AZ_FAIL=1 dispatch; rc=$?
check "AC4e vault error refused as a vault problem, not the assignee's" failed_vault

reset_env; seed_codex_job '{"active":1}'; dispatch --agent codex; rc=$?
busy_retry() { (( rc == 5 )) && ! grep -q "state=failed" "$CALLS" && [[ ! -d "$CLAIMS/wi-$CHANGE" ]]; }
check "AC4f busy codex assignee: exit 5, not Failed, claim released for a retry" busy_retry
handled() { (( rc == 3 )) && nothing_applied && ! grep -q "state=failed" "$CALLS"; }
for tag in fleet:dispatched Fleet:Refused " fleet:dispatched "; do
  reset_env; WI_JSON="{\"fields\":{\"System.AssignedTo\":{\"uniqueName\":\"Alice@Contoso.com\"},\"System.Tags\":\"fleet:auto;$tag\"}}" dispatch; rc=$?
  check "AC4g already handled ('$tag') exits 3 and creates nothing" handled
done
reset_env; WI_JSON='{"fields":{"System.AssignedTo":{"uniqueName":"Alice@Contoso.com"},"System.Tags":"fleet:auto; fleet:dispatched"}}' \
  dispatch --force; rc=$?
check "AC4g --force dispatches a change already handled" accepted
finish
