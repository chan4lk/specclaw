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
scenario "$APPROVED" 4 warn "dispatch refused (exit 4) warns, does not fail"
scenario "$APPROVED" 1 error "dispatch error fails the step"
scenario '{"phase":"prop' 0 error "truncated state.json"
scenario '[]' 0 error "array state.json"
scenario '"x"' 0 error "string state.json"
finish
