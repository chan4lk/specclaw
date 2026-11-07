#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster

reset_env; CODEX_JOB_JSON='{"status":{"active":1}}' dispatch --agent codex; active_rc=$?
reset_env; mkdir "$APPLIED/claim-fleet-codex-$H"
CODEX_JOB_JSON='{"status":{"succeeded":1}}' dispatch --agent codex; finished_rc=$?
reset_env
"$FLEET" dispatch "$CHANGE" --agent codex > "$TMP/race1" 2>&1 & p1=$!
"$FLEET" dispatch "$CHANGE" --agent codex > "$TMP/race2" 2>&1 & p2=$!
wait "$p1"; r1=$?; wait "$p2"; r2=$?
reset_env; CODEX_JOB_JSON='{"status":{"active":1}}' dispatch --agent claude; claude_rc=$?

serialized() { (( active_rc != 0 && finished_rc == 0 )); }
race_single_winner() {
  (( (r1 == 0) + (r2 == 0) == 1 )) && grep -qh "unfinished codex job" "$TMP/race1" "$TMP/race2"
}
claude_unbounded() { (( claude_rc == 0 )) && ! grep -q "get job fleet-codex" "$CALLS"; }

check "AC6 codex refused while active, allowed once the finished Job is replaced" serialized
check "AC6 two concurrent codex dispatches: exactly one wins" race_single_winner
check "AC6 claude never refused for concurrency" claude_unbounded
finish
