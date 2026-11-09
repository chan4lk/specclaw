#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
yq_py() { python3 -c "import sys,yaml,json; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" "$1"; }
H="$FLEET_ROOT/pipelines/dispatch-hosted.yml" S="$FLEET_ROOT/pipelines/dispatch.yml"
one_job() {
  local t; for t in "$H" "$S"; do
    yq_py "$t" | jq -e 'has("steps") | not' >/dev/null && yq_py "$t" | jq -e '(.jobs | length) == 1 and .jobs[0].job == "dispatch" and .jobs[0].timeoutInMinutes == 10' >/dev/null || return 1
  done
}
sparse_checkout() {
  local t; for t in "$H" "$S"; do
    yq_py "$t" | jq -e '.jobs[0].steps[0] | .checkout == "self" and .fetchDepth == 1 and .persistCredentials == true and .sparseCheckoutDirectories == ".specclaw"' >/dev/null || return 1
  done
  grep -q 'git show "origin/$trusted:.specclaw/config.yaml"' "$H"
}
lean_fetch() {
  local f; f="$(yq_py "$H" | jq -r '.jobs[0].steps[] | select(.displayName? == "Fetch specclaw-fleet at a pinned ref") | .script')"
  grep -q 'sparse-checkout set plugins/specclaw-fleet plugins/specclaw-sync' <<<"$f" && grep -q 'fetch -q --depth 1 --filter=blob:none' <<<"$f" \
    && grep -q 'rev-parse HEAD)" == "$ref"' <<<"$f"
}
docs() { grep -q '^## Hosted minutes' "$FLEET_ROOT/README.md" && grep -q '1,800 minutes a month' "$FLEET_ROOT/README.md" && grep -q 'Parallel jobs' "$FLEET_ROOT/README.md"; }
check "R051 AC-1 both templates run one job, dispatch, capped at 10 minutes" one_job
check "R051 AC-2 checkout is sparse to .specclaw, depth 1, with persisted credentials; the trusted config is still read" sparse_checkout
check "R051 AC-3 the pinned specclaw fetch is blob-less and sparse to the two fleet plugins, and still verifies the SHA" lean_fetch
check "R051 AC-4 the README explains the hosted-minute budget" docs
finish
