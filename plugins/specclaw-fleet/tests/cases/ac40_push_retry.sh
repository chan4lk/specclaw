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
fresh; PUSH_FAILS=9 FLEET_PUSH_ATTEMPTS=3 AGENT_RC=5 run_entry; all="$(cat "$CALLS")"; all_pushes="$(pushes)"; all_exit="$(cat "$TMP/status/exit")"; all_posts="$(posts)"
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

retries() { [[ "$once_pushes" == "push push " ]] && grep -q "state=pr_open" <<<"$once" && ! grep -q "push_error" <<<"$once"; }
gives_up() {
  [[ "$all_pushes" == "push push repack push " && "$all_exit" == 4 && "$all_posts" == 0 ]] \
    && grep -q "state=failed exit=push-failed push_error=fatal: push failed" <<<"$all" && ! grep -q "pullrequests" "$TMP/curl.log" 2>/dev/null
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
check "AC4 HEAD on the base branch: no push, no PR, exit code unchanged" base_ok
finish
