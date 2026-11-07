#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"
resume_rows=1
for row in "LS_FAIL=1|resume-failed" "REMOTE_BRANCH=specclaw/049-x FETCH_FAIL=1|resume-failed" "REMOTE_BRANCH=specclaw/049-x|run" "REMOTE_BRANCH=|run"; do
  eval "${row%%|*} run_entry"
  calls="$(cat "$CALLS")"
  if [[ "${row#*|}" == resume-failed ]]; then
    grep -q "state=failed exit=resume-failed" <<<"$calls" && ! grep -q "^claude -p" <<<"$calls" && ! grep -q " push " <<<"$calls" \
      || { resume_rows=0; echo "  ${row%%|*}: expected resume-failed and no agent"; }
  else
    grep -q "^claude -p" <<<"$calls" && ! grep -q "resume-failed" <<<"$calls" || { resume_rows=0; echo "  ${row%%|*}: expected the agent to run"; }
  fi
done
resume_stops() { (( resume_rows == 1 )); }
check "R10 a failed branch lookup, fetch or checkout stops the run (resume-failed); found or absent branches run" resume_stops

deadline_rows=1
for agent in claude codex; do
  AGENT_SLEEP=5 FLEET_AGENT_TIMEOUT=1 ENTRY_AGENT="$agent" run_entry; calls="$(cat "$CALLS")"
  [[ "$(cat "$TMP/status/exit")" == 143 ]] && grep -q "push -q -u origin HEAD" <<<"$calls" \
    && grep -q "state=pr_open exit=deadline branch=specclaw/049-x pr=.*pullrequest/77 draft=true" <<<"$calls" \
    || { deadline_rows=0; echo "  $agent: deadline did not push and open the PR"; }
done
LS_FAIL=1 run_entry; early_calls="$(cat "$CALLS")"
saves_on_deadline() { (( deadline_rows == 1 )) && ! grep -q " push " <<<"$early_calls"; }
check "R11 a deadline pushes the change branch and opens the (draft) PR for claude and codex; nothing is pushed before the workspace exists" saves_on_deadline

pending_rows=1
for template in dispatch.yml dispatch-hosted.yml; do
  for row in 'build|approved|049-x|yes' 'build|approved||no' 'proposal|approved||yes' 'proposal|draft|049-x|no' 'build|draft|049-x|no'; do
    IFS='|' read -r phase status only want <<<"$row"
    out="$(PIPELINE_FILE="$template" FLEET_ONLY_CHANGE="$only" bash -c '
      source "$1/tests/lib/harness.sh"; source "$1/tests/lib/pipeline-env.sh"; export FLEET_ONLY_CHANGE="$3"
      run_with_state 049-x "$2"; cat "$TMP/refs" 2>/dev/null' _ "$FLEET_ROOT" \
      "{\"phase\":\"$phase\",\"phases\":{\"proposal\":{\"status\":\"$status\"}}}" "$only")"
    got=no; [[ "$out" == *ref=* ]] && got=yes
    [[ "$got" == "$want" ]] || { pending_rows=0; echo "  $template $row: dispatched=$got"; }
  done
done
pending_same() { (( pending_rows == 1 )); }
check "R10 a named change dispatches on approval alone (as trigger and dispatch do); the scan also needs phase=proposal" pending_same

D="$FLEET_ROOT/image/Dockerfile"
prompt_plugins="$(grep -m1 '^PROMPT=' "$FLEET_ROOT/image/entrypoint.sh" | grep -oE 'specclaw(-[a-z]+)?' | sort -u)"
installed() {
  [[ -n "$prompt_plugins" ]] || return 1
  local p; for p in $prompt_plugins; do grep -q "plugin install $p@chan4lk" "$D" || { echo "  not installed: $p"; return 1; }; done
  grep -q "specclaw-review" <<<"$prompt_plugins"
}
pinned() { [[ -z "$(grep '^FROM ' "$D" | grep -v '@sha256:[0-9a-f]\{64\}')" ]]; }
check "R10 every plugin the agent prompt names is installed in the image seed" installed
check "R10 every base image is pinned by digest" pinned
finish
