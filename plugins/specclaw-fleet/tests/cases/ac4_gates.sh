#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster

refused() { (( rc != 0 )) && nothing_applied; }
refused_and_failed() { refused && marked_failed; }
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
  check "AC4d no consent (tags '$tags') refused and marked Failed" refused_and_failed
done

reset_env; echo __unset__ > "$KV/claude-token-$H"
dispatch; rc=$?; check "AC4e placeholder credential refused as unregistered" failed_unregistered
reset_env; rm "$KV/claude-token-$H"
dispatch; rc=$?; check "AC4e missing credential refused as unregistered" failed_unregistered
reset_env; AZ_FAIL=1 dispatch; rc=$?
check "AC4e vault error refused as a vault problem, not the assignee's" failed_vault

reset_env; CODEX_JOB_JSON='{"status":{"active":1}}' dispatch --agent codex; rc=$?
check "AC4f busy codex assignee refused and marked Failed" refused_and_failed
finish
