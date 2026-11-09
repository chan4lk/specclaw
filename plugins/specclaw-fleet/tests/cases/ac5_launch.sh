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
job="$(grep -l "^kind: Job" "$APPLIED"/*.yaml)" secret="$(grep -l "^kind: Secret" "$APPLIED"/*.yaml)"

one_secret_one_job() {
  (( rc == 0 )) && [[ $(find "$APPLIED" -type f | wc -l | tr -d " ") == 2 ]] && [[ -n "$job" && -n "$secret" ]] && grep -q "^kind: Secret" "$secret" && grep -q "^kind: Job" "$job"
}
secret_holds_credential() {
  grep -q "credential: $(printf '%s' "$CANARY" | base64 | tr -d '\n')" "$secret" && grep -A1 ownerReferences "$secret" | grep -q 'kind: Job, name: fleet-049-[0-9a-f]*, uid: "uid-[0-9]*-[0-9]*"' 
}
job_labels_and_deadline() {
  grep -q "specclaw.fleet/agent: claude" "$job" && grep -q "specclaw.fleet/assignee: \"$H\"" "$job" \
    && grep -q 'specclaw.fleet/change: "049-x"' "$job" && grep -q "activeDeadlineSeconds: 7800" "$job" && grep -q "FLEET_AGENT_TIMEOUT, value: \"7200\"" "$job"
}
job_hardened() {
  grep -q "automountServiceAccountToken: false" "$job" && grep -q "runAsNonRoot: true" "$job" && grep -q "seccompProfile: {type: RuntimeDefault}" "$job" \
    && grep -q "readOnlyRootFilesystem: true" "$job" && grep -q "backoffLimit: 0" "$job"
}
tagged_dispatched() { grep -q "specclaw-azdo-issue claim .* 049-x fleet:dispatched fleet:refused" "$CALLS" && [[ -d "$CLAIMS/wi-049-x" ]]; }
work_item_and_output() {
  grep -q "fields .*agent=claude .*cluster=k3s-a .*requested_by=Alice A dispatched_commit=[0-9a-f]\{40\} image=ghcr.io/chan4lk/specclaw-fleet:$(jq -r .version "$FLEET_ROOT/.claude-plugin/plugin.json") claude_version=2.1.319 settings_commit=local state=dispatched" "$CALLS" \
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
check "AC5 work item tagged fleet:dispatched so reruns skip it" tagged_dispatched
check "NFR3 no credential or PAT in output or Job" no_secret_leak
check "AC5 --dry-run redacts and applies nothing" dry_run_redacted
finish
