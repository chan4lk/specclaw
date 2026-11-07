#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster

race() {
  "$FLEET" dispatch "$CHANGE" --agent codex > "$TMP/race1" 2>&1 & local p1=$!
  "$FLEET" dispatch "$CHANGE" --agent codex > "$TMP/race2" 2>&1 & local p2=$!
  local r1=0 r2=0
  wait "$p1" || r1=$?
  wait "$p2" || r2=$?
  (( (r1 == 0) + (r2 == 0) == 1 ))
}

reset_env; seed_codex_job '{"active":1}'; dispatch --agent codex; active_rc=$?
finished_ok=1
for status in '{"succeeded":1}' '{"failed":1}' '{"conditions":[{"type":"Failed","status":"True"}]}'; do
  reset_env; seed_codex_job "$status"; dispatch --agent codex || finished_ok=0
done
reset_env; race; race_empty=$?
reset_env; seed_codex_job '{"succeeded":1}'; race; race_finished=$?
reset_env; seed_codex_job '{"active":1}'; dispatch --agent claude; claude_rc=$?

serialized() { (( active_rc != 0 && finished_ok == 1 )); }
single_winner() { (( race_empty == 0 && race_finished == 0 )); }
claude_unbounded() { (( claude_rc == 0 )) && ! grep -q "get job fleet-codex" "$CALLS"; }

check "AC6 codex refused while active; replaced once finished (succeeded, failed, Failed condition)" serialized
check "AC6 two concurrent codex dispatches, from empty and from a finished Job: exactly one wins" single_winner
check "AC6 claude never refused for concurrency" claude_unbounded
finish
