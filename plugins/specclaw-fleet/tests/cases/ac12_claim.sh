#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster

reset_env; CLAIM_FAIL=1 dispatch; rc=$?
claim_error() { (( rc == 1 )) && nothing_applied && grep -q "could not claim" "$TMP/out"; }
check "AC12 a claim that errors exits 1 (never 3, never a silent skip)" claim_error

for kind in Job Secret; do
  for err in "Error from server (Forbidden): cannot create" "Unable to connect to the server: dial tcp" "Error from server: i/o timeout"; do
    reset_env; CREATE_KIND="$kind" CREATE_ERR="$err" dispatch; rc=$?
    released() {
      (( rc == 1 )) && [[ ! -d "$CLAIMS/wi-$CHANGE" ]] && grep -q "untag .* fleet:dispatched" "$CALLS" \
        && { [[ "$kind" == Job ]] || { grep -q "could not create Secret" "$TMP/out" && grep -q " delete job " "$CALLS"; }; }
    }
    check "AC12 $kind create fails (${err:0:30}…): claim released, exit 1" released
  done
done

reset_env; CREATE_ERR="Error from server (Forbidden)" UNTAG_FAIL=1 dispatch; rc=$?
release_warns() { (( rc == 1 )) && grep -q "could not release the fleet:dispatched claim" "$TMP/out"; }
check "AC12 a failed release warns and still exits with the creation error" release_warns
finish
