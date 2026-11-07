#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/pipeline-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/pipeline-env.sh"
stub git '[[ -n "${GIT_SHOW_FAIL:-}" && "$1" == show ]] && { echo "fatal: unable to read object" >&2; exit 128; }
exec "$REAL_GIT" "$@"'
EDITED='{"phases":{"proposal":{"status":"approved"},"plan":{"status":"done"}}}'

scenario() {
  local before="$1" after="$2" expect="$3" label="$4"
  new_repo && put_state "$before" && put_state "$after"
  run_step
  local rc=$? got=skip
  dispatched && got=dispatch
  (( rc != 0 )) && got=error
  outcome() { [[ "$got" == "$expect" ]]; }
  check "FR10 $label → $expect" outcome
}

scenario "$DRAFT" "$OK" dispatch "draft to approved"
scenario - "$OK" dispatch "added already approved"
scenario "$OK" "$EDITED" skip "approved to approved edit"
scenario "$OK" - skip "deleted"
scenario "$DRAFT" '{"phases":{' error "truncated at HEAD"
scenario "$DRAFT" '[]' error "array at HEAD"
scenario "$DRAFT" '"x"' error "string at HEAD"
scenario '{"phases"' "$OK" error "truncated at HEAD^1"
GIT_SHOW_FAIL=1 scenario "$DRAFT" "$OK" error "git cannot read the object"
new_repo && put_state -
run_step; solo_rc=$?
no_parent_fails() { (( solo_rc != 0 )) && grep -q "could not list changed state files" "$TMP/out"; }
check "FR10 no parent commit fails the step" no_parent_fails
finish
