#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/pipeline-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/pipeline-env.sh"
stub curl '[[ -n "${CURL_FAIL:-}" ]] && exit 22; echo "$BUILDS_JSON"'
export SYSTEM_TEAMPROJECTID=p SYSTEM_DEFINITIONID=7 BUILD_SOURCEBRANCH=refs/heads/main

new_repo && put_state "$DRAFT"
green="$(git -C "$TMP/r" rev-parse HEAD)"
put_state "$OK" && put_state "$OK"

SYSTEM_ACCESSTOKEN=t BUILDS_JSON="{\"value\":[{\"sourceVersion\":\"$green\"}]}" run_step; multi_rc=$?
dispatched; multi=$?
SYSTEM_ACCESSTOKEN=t BUILDS_JSON='{"value":[]}' run_step; first_rc=$?
dispatched; first=$?
SYSTEM_ACCESSTOKEN=t CURL_FAIL=1 run_step; api_rc=$?

sees_whole_push() { (( multi_rc == 0 && multi == 0 )); }
first_run_uses_parent() { (( first_rc == 0 && first != 0 )); }
api_failure_fails() { (( api_rc != 0 )) && grep -q "could not read the last successful run" "$TMP/out"; }

check "FR10 an approval earlier in a multi-commit push is seen (diff from last green run)" sees_whole_push
check "FR10 no previous green run falls back to the parent commit" first_run_uses_parent
check "FR10 a failed run-history lookup fails the step" api_failure_fails
finish
