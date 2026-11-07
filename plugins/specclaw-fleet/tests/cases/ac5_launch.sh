#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
reset_env
BUILD_REQUESTEDFOR="Alice A" dispatch
rc=$?
job="$APPLIED/0.yaml" secret="$APPLIED/1.yaml"

one_secret_one_job() {
  (( rc == 0 )) && [[ $(find "$APPLIED" -type f | wc -l | tr -d " ") == 2 ]] && grep -q "^kind: Secret" "$secret" && grep -q "^kind: Job" "$job"
}
secret_holds_credential() {
  grep -q "credential: $(printf '%s' "$CANARY" | base64 | tr -d '\n')" "$secret" && grep -A1 ownerReferences "$secret" | grep -q 'kind: Job, name: fleet-049-[0-9a-f]*, uid: "uid-1"' 
}
job_labels_and_deadline() {
  grep -q "specclaw.fleet/agent: claude" "$job" && grep -q "specclaw.fleet/assignee: \"$H\"" "$job" \
    && grep -q 'specclaw.fleet/change: "049-x"' "$job" && grep -q "activeDeadlineSeconds: 7200" "$job"
}
job_hardened() {
  grep -q "automountServiceAccountToken: false" "$job" && grep -q "runAsNonRoot: true" "$job" \
    && grep -q "readOnlyRootFilesystem: true" "$job" && grep -q "backoffLimit: 0" "$job"
}
work_item_and_output() {
  grep -q "fields .*agent=claude .*cluster=k3s-a .*requested_by=Alice A state=dispatched" "$CALLS" \
    && jq -e '.ok == true and .agent == "claude" and .work_item == "42"' "$TMP/out" >/dev/null
}
no_secret_leak() { ! grep -q "$CANARY" "$TMP/out" "$job" && ! grep -q "user:pat" "$job"; }
dry_run_redacted() {
  reset_env && dispatch --dry-run && grep -q "credential: REDACTED" "$TMP/out" && nothing_applied
}

check "AC5 exactly one Secret and one Job applied" one_secret_one_job
check "AC5 Secret holds only the credential and is owned by the Job" secret_holds_credential
check "AC5 Job carries the three labels and the deadline" job_labels_and_deadline
check "AC10 rendered Job is hardened" job_hardened
check "AC5 work item gets Dispatched and run fields; JSON line printed" work_item_and_output
check "NFR3 no credential or PAT in output or Job" no_secret_leak
check "AC5 --dry-run redacts and applies nothing" dry_run_redacted
finish
