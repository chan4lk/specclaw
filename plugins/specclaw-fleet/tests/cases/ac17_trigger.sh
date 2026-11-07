#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
export AZDO_ORG=o AZDO_PROJECT=p FLEET_REMOTE=local
publish() {
  rm -rf "$TMP/remote.git" && git init -q --bare "$TMP/remote.git"
  git -C "$TMP/repo" remote remove local 2>/dev/null; git -C "$TMP/repo" remote add local "$TMP/remote.git"
  git -C "$TMP/repo" add -A && git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q -m state
  git -C "$TMP/repo" push -q local HEAD:main
}
trig() { "$FLEET" trigger "$CHANGE" "$@" > "$TMP/out" 2>&1; }
quiet() { ! grep -qE "pipelines run|azdo-issue (fields|tag|untag|claim|create)" "$CALLS" && nothing_applied; }
gate() { local want_rc="$1" want_msg="$2"; ok() { (( rc == want_rc )) && grep -q "$want_msg" "$TMP/out" && quiet; }; check "AC8 gate: $want_msg (no untag/create/fields/tag/claim/pipeline call)" ok; }

reset_env; publish; echo '{"phases":{"proposal":{"status":"draft"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"; trig; remote_rc=$?
remote_truth() { (( remote_rc == 0 )) && grep -q "pipelines run" "$CALLS"; }
check "AC8 approval is read from the pushed ref, not the local tree" remote_truth
reset_env; echo '{"phases":{"proposal":{"status":"draft"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"; publish
echo '{"phases":{"proposal":{"status":"approved"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"; trig; rc=$?
gate 1 "approve it and push first"
reset_env; publish; : > "$SPECCLAW_DIR/changes/$CHANGE/status.md"; trig; rc=$?; gate 1 "pass --create"
reset_env; publish; WI_JSON='{"fields":{"System.Tags":"fleet:auto"}}' trig; rc=$?; gate 4 "work item has no assignee"
reset_env; publish; WI_JSON='{"fields":{"System.AssignedTo":{"uniqueName":"alice@contoso.com"},"System.Tags":"specclaw"}}' trig; rc=$?
gate 3 "not opted in (no fleet:auto tag)"
reset_env; publish; WI_UPDATES='{"value":[{"revisedBy":{"uniqueName":"m@c.com"},"fields":{"System.Tags":{"newValue":"fleet:auto"}}}]}' trig; rc=$?
gate 4 "fleet:auto was not added by the assignee"
reset_env; publish; WI_UPDATES=FAIL trig; rc=$?; gate 4 "could not read the work item history"
reset_env; publish; rm "$KV/claude-token-$H"; trig; rc=$?; gate 4 "no registered claude credential"

reset_env; publish; : > "$SPECCLAW_DIR/changes/$CHANGE/status.md"; trig --create; create_rc=$?; create_calls="$(cat "$CALLS")"; create_out="$(cat "$TMP/out")"
reset_env; publish; trig; queue_rc=$?; queue_out="$(cat "$TMP/out")"; queue_calls="$(cat "$CALLS")"
reset_env; publish; trig --retry; retry_calls="$(cat "$CALLS")"
reset_env; publish; trig --direct; direct_rc=$?; direct_out="$(cat "$TMP/out")"; direct_jobs="$(find "$APPLIED" -name '*.yaml' | wc -l | tr -d ' ')"
reset_env; echo '{"phases":{"proposal":{"status":"draft"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"; publish; : > "$SPECCLAW_DIR/changes/$CHANGE/status.md"
trig --retry --create; rc=$?; gate 1 "approve it and push first"
reset_env; publish; WI_UPDATES='{"value":[{"revisedBy":{"uniqueName":"m@c.com"},"fields":{"System.Tags":{"newValue":"fleet:auto"}}}]}' trig --retry; rc=$?
gate 4 "fleet:auto was not added by the assignee"
reset_env; publish; GET_ERR="Error from server (Forbidden): jobs" FLEET_DEFAULT_AGENT=codex trig; unread_rc=$?; unread_out="$(cat "$TMP/out")"
reset_env; publish; rm "$KV/claude-token-$H"
WI_JSON='{"fields":{"System.AssignedTo":{"uniqueName":"Alice@Contoso.com"},"System.Tags":"fleet:auto; fleet:refused"}}' trig --retry; rc=$?
gate 4 "no registered claude credential"
reset_env; publish; : > "$SPECCLAW_DIR/changes/$CHANGE/status.md"; rm "$KV/claude-token-$H"; trig --create; cc_rc=$?; cc_calls="$(cat "$CALLS")"
create_then_stop() { (( cc_rc == 3 )) && grep -q "azdo-issue create" <<<"$cc_calls" && ! grep -qE "untag|fields|azdo-issue tag|claim|pipelines run" <<<"$cc_calls"; }
check "AC8 --create creates even when a later gate would fail (a new item can never pass assignee/consent), then stops before any other write" create_then_stop
junk_notrun=1
for raw in "" "not json" "[1]" '"x"' '{"status":{"succeeded":1}}'; do
  reset_env; publish; JOB_RAW="$raw" FLEET_DEFAULT_AGENT=codex trig || junk_notrun=0
  jq -e '.codex_busy_check | startswith("not-run")' "$TMP/out" >/dev/null 2>&1 || junk_notrun=0
done
junk_reported() { (( junk_notrun == 1 )); }
check "AC8 junk Job JSON makes trigger's busy check not-run for every payload" junk_reported
unread() { (( unread_rc == 0 )) && jq -e '.codex_busy_check | startswith("not-run")' <<<"$unread_out" >/dev/null; }
check "AC8 an unreadable cluster makes the busy check not-run, never clear" unread
creates() { (( create_rc == 3 )) && grep -q "azdo-issue create" <<<"$create_calls" && ! grep -q "pipelines run" <<<"$create_calls" && grep -q "assign it" <<<"$create_out"; }
queues() {
  (( queue_rc == 0 )) && jq -e '.mode == "queued" and .run == "4242" and .change == "049-x" and .agent == "claude"' <<<"$queue_out" >/dev/null \
    && grep -q "pipelines run .*--parameters change=049-x agent=claude" <<<"$queue_calls" && ! grep -q untag <<<"$queue_calls"
}
retries() { grep -q "untag .* fleet:dispatched" <<<"$retry_calls" && grep -q "untag .* fleet:refused" <<<"$retry_calls"; }
directs() { (( direct_rc == 0 )) && jq -e '.ok == true and .job' <<<"$direct_out" >/dev/null && [[ "$direct_jobs" == 2 ]]; }
check "AC8 --create creates the work item and stops (exit 3) so it can be assigned" creates
check "AC8 default path queues the pipeline for exactly this change and agent" queues
check "AC8 --retry clears fleet:dispatched and fleet:refused" retries
check "AC8 --direct dispatches a Job instead of queueing" directs
finish
