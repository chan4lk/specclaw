#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
export AZDO_ORG=o AZDO_PROJECT=p
trig() { "$FLEET" trigger "$CHANGE" "$@" > "$TMP/out" 2>&1; }
stopped() { (( rc == $1 )) && grep -q "$2" "$TMP/out" && ! grep -qE "pipelines run|azdo-issue (fields|tag|claim)" "$CALLS" && nothing_applied; }
gate() { local want_rc="$1" want_msg="$2"; shift 2; rc_check() { stopped "$want_rc" "$want_msg"; }; check "AC8 gate: $want_msg" rc_check; }

reset_env; echo '{"phases":{"proposal":{"status":"draft"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"; trig; rc=$?; gate 1 "proposal is not approved"
reset_env; : > "$SPECCLAW_DIR/changes/$CHANGE/status.md"; trig; rc=$?; gate 1 "pass --create"
reset_env; WI_JSON='{"fields":{"System.Tags":"fleet:auto"}}' trig; rc=$?; gate 1 "has no assignee"
reset_env; WI_JSON='{"fields":{"System.AssignedTo":{"uniqueName":"alice@contoso.com"},"System.Tags":"specclaw"}}' trig; rc=$?
gate 4 "alice@contoso.com must add the fleet:auto tag"
reset_env; WI_UPDATES='{"value":[{"revisedBy":{"uniqueName":"mallory@c.com"},"fields":{"System.Tags":{"newValue":"fleet:auto"}}}]}' trig; rc=$?
gate 4 "must add the fleet:auto tag"
reset_env; WI_UPDATES=FAIL trig; rc=$?; gate 1 "could not read the work item history"
reset_env; rm "$KV/claude-token-$H"; trig; rc=$?; gate 1 "specclaw-fleet login --agent claude"

reset_env; : > "$SPECCLAW_DIR/changes/$CHANGE/status.md"; trig --create; create_rc=$?; create_calls="$(cat "$CALLS")"
reset_env; trig; queue_rc=$?; queue_out="$(cat "$TMP/out")"; queue_calls="$(cat "$CALLS")"
reset_env; trig --retry; retry_calls="$(cat "$CALLS")"
reset_env; trig --direct; direct_rc=$?; direct_out="$(cat "$TMP/out")"; direct_jobs="$(find "$APPLIED" -name '*.yaml' | wc -l | tr -d ' ')"
creates() { (( create_rc == 0 )) && grep -q "specclaw-azdo-issue create" <<<"$create_calls" && grep -q "pipelines run" <<<"$create_calls"; }
queues() { (( queue_rc == 0 )) && jq -e '.mode == "pipeline" and .run == "4242" and .work_item == "42"' <<<"$queue_out" >/dev/null && ! grep -q untag <<<"$queue_calls"; }
retries() { grep -q "untag .* fleet:dispatched" <<<"$retry_calls" && grep -q "untag .* fleet:refused" <<<"$retry_calls"; }
directs() { (( direct_rc == 0 )) && jq -e '.ok == true and .job' <<<"$direct_out" >/dev/null && [[ "$direct_jobs" == 2 ]]; }
check "AC8 --create creates the missing work item, then queues" creates
check "AC8 default path queues the pipeline and prints the run, without untagging" queues
check "AC8 --retry clears fleet:dispatched and fleet:refused" retries
check "AC8 --direct dispatches a Job instead of queueing" directs
finish
