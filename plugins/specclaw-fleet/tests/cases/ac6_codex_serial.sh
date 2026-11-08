#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster

race() {
  add_change 049-y
  "$FLEET" dispatch "$CHANGE" --agent "${1:-codex}" > "$TMP/race1" 2>&1 & local p1=$!
  "$FLEET" dispatch "${2:-049-y}" --agent "${1:-codex}" > "$TMP/race2" 2>&1 & local p2=$!
  local r1=0 r2=0
  wait "$p1" || r1=$?
  wait "$p2" || r2=$?
  (( (r1 == 0) + (r2 == 0) == 1 ))
}

active_refused=1
for status in '{"active":1}' '{"failed":1,"active":1}' '{}'; do
  reset_env; seed_codex_job "$status"; dispatch --agent codex && active_refused=0
done
reset_env; seed_codex_job '{"succeeded":1}'; SWAP_BEFORE_DELETE=1 dispatch --agent codex; swap_rc=$?
swap_uid="$(cat "$CLAIMS/claim-fleet-codex-$H/uid")" swap_out="$(cat "$TMP/out")"
finished_ok=1
for status in '{"succeeded":1}' '{"failed":1}' '{"conditions":[{"type":"Failed","status":"True"}]}'; do
  reset_env; seed_codex_job "$status"; dispatch --agent codex || finished_ok=0
done
reset_env; race; race_empty=$?
reset_env; seed_codex_job '{"succeeded":1}'; race; race_finished=$?
reset_env; race claude "$CHANGE"; same_change=$?; same_jobs="$(grep -l "^kind: Job" "$APPLIED"/*.yaml 2>/dev/null | wc -l | tr -d ' ')"
reset_env; seed_codex_job '{"active":1}'; dispatch --agent claude; claude_rc=$? claude_calls="$(cat "$CALLS")"
delete_errors_surface=1
for err in "Error from server (Forbidden): cannot delete" "Unable to connect to the server: dial tcp" "Error from server: i/o timeout"; do
  reset_env; seed_codex_job '{"succeeded":1}'; DELETE_ERR="$err" dispatch --agent codex && delete_errors_surface=0
  grep -q "could not replace finished Job" "$TMP/out" && ! grep -q "unfinished codex job" "$TMP/out" || delete_errors_surface=0
done
read_errors_refused=1
for err in "Error from server (Forbidden): jobs is forbidden" "Unable to connect to the server: dial tcp 10.0.0.1:6443" "Error from server: i/o timeout"; do
  reset_env; GET_ERR="$err" dispatch --agent codex && read_errors_refused=0
  [[ -z "$(ls -A "$CLAIMS")" ]] && nothing_applied || read_errors_refused=0
done

serialized() { (( active_refused == 1 && finished_ok == 1 )); }
newer_run_survives() { (( swap_rc != 0 )) && [[ "$swap_uid" == new-uid ]] && grep -q "unfinished codex job" <<<"$swap_out"; }
single_winner() { (( race_empty == 0 && race_finished == 0 )); }
one_claim() { (( same_change == 0 )) && [[ "$same_jobs" == 1 ]]; }
check "AC6 two concurrent dispatches of one change: the work-item claim lets exactly one through" one_claim
claude_unbounded() { (( claude_rc == 0 )) && ! grep -q "get job fleet-codex" <<<"$claude_calls"; }

check "AC6 codex refused while active; replaced once finished (succeeded, failed, Failed condition)" serialized
check "AC6 a newer run created between read and delete is never deleted (UID precondition)" newer_run_survives
check "AC6 one assignee, two changes, concurrent codex: exactly one wins (from empty and from a finished Job)" single_winner
junk_refused=1
for raw in "" "not json" "[1]" '"x"' '{"status":{"succeeded":1}}'; do
  reset_env; JOB_RAW="$raw" dispatch --agent codex && junk_refused=0
  reset_env; JOB_RAW="$raw" "$FLEET" trigger "$CHANGE" > /dev/null 2>&1 || true
done
junk_closed() { (( junk_refused == 1 )); }
check "AC6 empty, unparsable, non-object or uid-less Job JSON never reads as a free slot" junk_closed
fail_closed() { (( read_errors_refused == 1 )); }
delete_fail_closed() { (( delete_errors_surface == 1 )); }
check "AC6 a delete error other than a UID conflict surfaces the real error" delete_fail_closed
check "AC6 a Job read error other than NotFound refuses and creates nothing" fail_closed
check "AC6 claude never refused for concurrency" claude_unbounded
finish
