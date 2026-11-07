#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/pipeline-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/pipeline-env.sh"

new_repo && put_state "$DRAFT"
green="$(git -C "$TMP/r" rev-parse HEAD)"
put_state "$OK" && put_state "$OK"

SYSTEM_ACCESSTOKEN=t BUILDS_JSON="{\"value\":[{\"sourceVersion\":\"$green\"}]}" run_step; multi_rc=$?
dispatched; multi=$?
SYSTEM_ACCESSTOKEN=t BUILDS_JSON='{"value":[]}' run_step; first_rc=$?
dispatched; first=$?
SYSTEM_ACCESSTOKEN=t CURL_FAIL=1 run_step; api_rc=$?
api_out="$(cat "$TMP/out")"
SYSTEM_ACCESSTOKEN="" run_step; no_token_rc=$?

sees_whole_push() { (( multi_rc == 0 && multi == 0 )); }
first_run_uses_parent() { (( first_rc == 0 && first != 0 )); }
api_failure_fails() { (( api_rc != 0 )) && grep -q "could not read the last successful run" <<<"$api_out"; }
no_token_fails() { (( no_token_rc != 0 )) && grep -q "could not read the last successful run" "$TMP/out"; }

check "FR10 an approval earlier in a multi-commit push is seen (diff from last green run)" sees_whole_push
check "FR10 no previous green run falls back to the parent commit" first_run_uses_parent
check "FR10 a failed run-history lookup fails the step" api_failure_fails
check "FR10 a missing access token fails the step instead of narrowing the range" no_token_fails
finish
