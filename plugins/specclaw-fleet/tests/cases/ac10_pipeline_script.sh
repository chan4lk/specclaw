#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/pipeline-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/pipeline-env.sh"

scenario() {
  local state="$1" dispatch_rc="$2" expect="$3" label="$4" change="${5:-049-x}"
  DISPATCH_RC="$dispatch_rc" run_with_state "$change" "$state"
  local rc=$? got=skip
  grep -qxF "specclaw-fleet dispatch $change" "$CALLS" && got=dispatch
  (( rc != 0 )) && got="error"
  [[ "$got" == dispatch ]] && grep -q "warning" "$TMP/out" && got=warn
  outcome() { [[ "$got" == "$expect" ]]; }
  check "FR10 $label → $expect" outcome
}

scenario "$APPROVED" 0 dispatch "approved, not started"
scenario "$APPROVED" 0 dispatch "change name with spaces" "050 odd name"
scenario '{"phase":"build","phases":{"proposal":{"status":"approved"}}}' 0 skip "approved, already building"
scenario '{"phase":"proposal","phases":{"proposal":{"status":"draft"}}}' 0 skip "draft proposal"
scenario "$APPROVED" 3 dispatch "already handled by an earlier run (exit 3)"
scenario "$APPROVED" 5 warn "busy codex slot (exit 5) warns, does not fail"
scenario "$APPROVED" 4 warn "dispatch refused (exit 4) warns, does not fail"
scenario "$APPROVED" 1 error "dispatch error fails the step"
scenario '{"phase":"prop' 0 error "truncated state.json"
scenario '[]' 0 error "array state.json"
scenario '"x"' 0 error "string state.json"
FLEET_ONLY_CHANGE=" other-change " run_with_state 049-x "$APPROVED"; only_calls="$(cat "$CALLS")"
FLEET_ONLY_CHANGE=" 049-x " FLEET_RUN_AGENT=" codex " run_with_state 049-x "$APPROVED"; agent_calls="$(cat "$CALLS")"
FLEET_ONLY_CHANGE=" " FLEET_RUN_AGENT=" " run_with_state 049-x "$APPROVED"; blank_calls="$(cat "$CALLS")"
filters() { [[ -z "$only_calls" ]] && grep -qxF "specclaw-fleet dispatch 049-x --agent codex" <<<"$agent_calls" \
  && grep -qxF "specclaw-fleet dispatch 049-x" <<<"$blank_calls"; }
check "FR10 change and agent parameters narrow the run; blank parameters mean every change, default agent" filters
finish
