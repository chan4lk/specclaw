#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"
export FLEET_PUSH_PAUSES=0
posts() { grep -c -- "-X POST" "$TMP/curl.log" 2>/dev/null || true; }
fresh() { rm -f "$TMP/curl.log" "$TMP/pr-body.json"; }
pushes() { tr '\n' ' ' 2>/dev/null < "$TMP/pushes"; }
secret="ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD"

fresh; PUSH_FAILS=1 AGENT_RC=5 run_entry; once="$(cat "$CALLS")"; once_pushes="$(pushes)"
fresh; PUSH_FAILS=9 FLEET_PUSH_ATTEMPTS=3 AGENT_RC=5 run_entry; all="$(cat "$CALLS")"; all_pushes="$(pushes)"; all_exit="$(cat "$TMP/status/exit")"; all_posts="$(posts)"; all_curl="$(cat "$TMP/curl.log" 2>/dev/null)"
fresh; PUSH_FAILS=9 FLEET_PUSH_ATTEMPTS=1 PUSH_ERR=$'remote: hint\nfatal: auth sk-ant-oat01-LEAKED for '"$secret" AGENT_RC=5 run_entry
leak="$(cat "$CALLS")"; leak_pushes="$(pushes)"; leak_out="$(cat "$TMP/out")"
fresh; ON_BRANCH=main AGENT_RC=5 run_entry; base="$(cat "$CALLS")"; base_exit="$(cat "$TMP/status/exit")"; base_posts="$(posts)"; base_pushes="$(pushes)"
fresh; PUSH_FAILS=9 FLEET_PUSH_ATTEMPTS=1 AGENT_SLEEP=20 FLEET_AGENT_TIMEOUT=3 AGENT_RC=5 run_entry; dl="$(cat "$CALLS")"; dl_exit="$(cat "$TMP/status/exit")"
pause_rows=1
for row in "x|warn" "   |warn" "5;rm -rf /|warn" "1 a|warn" "-1|warn" "0 0|ok" " 0	1 |ok"; do
  PUSH_FAILS=9 FLEET_PUSH_ATTEMPTS=1 FLEET_PUSH_PAUSES="${row%|*}" AGENT_RC=5 run_entry; out="$(cat "$TMP/out")"
  { [[ "${row#*|}" == warn ]] && grep -q "WARNING: FLEET_PUSH_PAUSES is not seconds separated by spaces; using the default" <<<"$out"; } \
    || { [[ "${row#*|}" == ok ]] && ! grep -q "FLEET_PUSH_PAUSES" <<<"$out"; } || { pause_rows=0; echo "  pauses [${row%|*}]: wrong warning"; }
  ! grep -q "bad array subscript" <<<"$out" || { pause_rows=0; echo "  pauses [${row%|*}]: bad array subscript"; }
done
# A push that hangs is cut off after FLEET_PUSH_TIMEOUT and counts as a failed try.
hang_rows=1
while IFS='|' read -r vars want rec; do
  IFS=';' read -ra kv <<<"$vars"; ( export "${kv[@]}" FLEET_PUSH_TIMEOUT=1 AGENT_RC=5; run_entry )
  [[ "$(pushes)" == "$want" ]] && grep -q "push 1/[0-9] of specclaw/049-x failed: push timed out after 1s" "$TMP/out" && grep -q "$rec" "$CALLS" \
    || { hang_rows=0; echo "  hang [$vars]: pushes [$(pushes)]"; }
done <<'ROWS'
PUSH_HANGS=1;FLEET_PUSH_ATTEMPTS=2|push repack push |state=pr_open
PUSH_HANGS=2;PUSH_FAILS=2;FLEET_PUSH_ATTEMPTS=2|push repack push |exit=push-failed push_error=push timed out after 1s
PUSH_HANGS=1;PUSH_FAILS=9;FLEET_PUSH_ATTEMPTS=1|push |exit=push-failed push_error=push timed out after 1s
ROWS
# Pauses that would run past the delivery budget (agent deadline + 300 s) skip the later tries; the record and bundle still happen.
budget_rows=1
while IFS='|' read -r vars want; do
  mkdir -p "$TMP/bundles"
  vars="${vars/NEAR/$(( $(date +%s) + 195 ))}"; vars="${vars/PAST/$(( $(date +%s) - 5 ))}"
  IFS=';' read -ra kv <<<"$vars"; ( export "${kv[@]}" PUSH_FAILS=9 FLEET_PUSH_ATTEMPTS=3 AGENT_RC=5; run_entry )
  [[ "$(pushes)" == "$want" && "$(cat "$TMP/status/exit")" == 4 && -s "$TMP/bundles/work.bundle" ]] && grep -q "delivery budget spent; push" "$TMP/out" \
    && grep -qE "exit=push-failed .*push_error=(fatal: push failed|push skipped: delivery budget spent) bundle=saved" "$CALLS" || { budget_rows=0; echo "  budget [$vars]: pushes [$(pushes)]"; }
  rm -rf "$TMP/bundles"
done <<'ROWS'
FLEET_AGENT_TIMEOUT=60;FLEET_PUSH_PAUSES=400|push 
FLEET_AGENT_TIMEOUT=60;FLEET_PUSH_PAUSES=0 400|push push 
AGENT_SLEEP=20;FLEET_AGENT_TIMEOUT=2;FLEET_PUSH_PAUSES=299|push 
FLEET_HARD_DEADLINE=NEAR;FLEET_PUSH_PAUSES=20|push 
FLEET_HARD_DEADLINE=PAST;FLEET_PUSH_PAUSES=0|
ROWS
timeout_rows=1
for row in "x|warn" "0|warn" "-1|warn" "10000|warn" "1 2|warn" "5|ok"; do
  PUSH_FAILS=9 FLEET_PUSH_ATTEMPTS=1 FLEET_PUSH_TIMEOUT="${row%|*}" AGENT_RC=5 run_entry
  { [[ "${row#*|}" == warn ]] && grep -q "WARNING: FLEET_PUSH_TIMEOUT is not whole seconds from 1 to 9999; using the default" "$TMP/out"; } \
    || { [[ "${row#*|}" == ok ]] && ! grep -q FLEET_PUSH_TIMEOUT "$TMP/out"; } || { timeout_rows=0; echo "  timeout [${row%|*}]: wrong warning"; }
  [[ "$(pushes)" == "push " ]] || { timeout_rows=0; echo "  timeout [${row%|*}]: pushes [$(pushes)]"; }
done

retries() { [[ "$once_pushes" == "push push " ]] && grep -q "state=pr_open" <<<"$once" && ! grep -q "push_error" <<<"$once"; }
gives_up() {
  [[ "$all_pushes" == "push push repack push " && "$all_exit" == 4 && "$all_posts" == 0 ]] \
    && grep -q "state=failed exit=push-failed push_error=fatal: push failed" <<<"$all" && ! grep -q "pullrequests" <<<"$all_curl"
}
redacts() {
  [[ "$leak_pushes" == "push " ]] && grep -q "push_error=fatal: auth sk-ant-<redacted> for <redacted>" <<<"$leak" \
    && ! grep -qe "LEAKED" -e "$secret" <<<"$leak$leak_out"
}
deadline() { [[ "$dl_exit" == 4 ]] && grep -q "state=failed exit=push-failed cause=deadline push_error=" <<<"$dl" && ! grep -q cause= <<<"$all"; }
pauses_checked() { (( pause_rows == 1 )); }
base_ok() { [[ -z "$base_pushes" && "$base_exit" == 5 && "$base_posts" == 0 ]] && grep -q "pr=none" <<<"$base" && ! grep -q push-failed <<<"$base"; }

check "AC1 a push that fails once is retried and opens the PR, with no push_error" retries
check "AC2 a push that always fails: FLEET_PUSH_ATTEMPTS tries, repack before the last, exit=push-failed, exit code 4, no PR call" gives_up
check "AC3 push_error keeps git's last error line with tokens redacted (and one attempt means no repack)" redacts
check "FR-3 a deadline whose push fails records exit=push-failed cause=deadline and exits 4; an agent exit adds no cause" deadline
check "FR-1 FLEET_PUSH_PAUSES other than whole seconds and spaces (letters, blank, shell text, negative) warns and uses the default" pauses_checked
hang_cut() { (( hang_rows == 1 )); }
budget_spent() { (( budget_rows == 1 )); }
timeout_checked() { (( timeout_rows == 1 )); }
check "FR-1 a push that hangs is cut off after FLEET_PUSH_TIMEOUT, recorded as timed out, and retried" hang_cut
check "FR-1 a pause that would pass the delivery budget skips the later tries; exit=push-failed is recorded and the bundle saved (also on the deadline path)" budget_spent
check "FR-1 FLEET_PUSH_TIMEOUT other than 1-9999 whole seconds warns and uses the default" timeout_checked
check "AC4 HEAD on the base branch: no push, no PR, exit code unchanged" base_ok
finish
