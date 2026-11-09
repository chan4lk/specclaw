#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
reset_env; FLEET_MODE=integrate FLEET_MERGE_REF=feature/cat FLEET_PR_TARGET=main dispatch --dry-run; withenv="$(cat "$TMP/out")"
reset_env; dispatch --dry-run; plain="$(cat "$TMP/out")"
bad=1; for v in "FLEET_MODE=rebase" "FLEET_MERGE_REF=../x" "FLEET_PR_TARGET=-x"; do reset_env; env "$v" "$FLEET" dispatch "$CHANGE" --dry-run >/dev/null 2>&1 && bad=0; done
manifest_env() {
  grep -q '{name: FLEET_MODE, value: "integrate"}' <<<"$withenv" && grep -q '{name: FLEET_MERGE_REF, value: "feature/cat"}' <<<"$withenv" \
    && grep -q '{name: FLEET_PR_TARGET, value: "main"}' <<<"$withenv" && ! grep -q 'FLEET_MODE\|FLEET_MERGE_REF\|FLEET_PR_TARGET' <<<"$plain" && (( bad == 1 ))
}
check "R050 AC-5 the Job carries FLEET_MODE, FLEET_MERGE_REF and FLEET_PR_TARGET only when set, and refuses invalid values" manifest_env
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"
ENTRY_MODE=integrate ENTRY_REF=feature/049-x ENTRY_PR_TARGET=main run_entry; ok_calls="$(cat "$CALLS")"; ok_pr="$(cat "$TMP/pr-body.json" 2>/dev/null)"
ENTRY_MODE=integrate ENTRY_REF=feature/049-x ENTRY_PR_TARGET=main AGENT_RC=3 run_entry; bad_pr="$(cat "$TMP/pr-body.json" 2>/dev/null)"
ENTRY_MODE=integrate NOT_APPROVED=1 run_entry; na_calls="$(cat "$CALLS")"
integrate_pod() {
  grep -q "^claude -p Integrate feature 049-x" <<<"$ok_calls" && grep -q "checkout -q -b specclaw/integrate-049-x" <<<"$ok_calls" \
    && grep -q "push -q -u origin HEAD" <<<"$ok_calls" && grep -q "branch=specclaw/integrate-049-x" <<<"$ok_calls" \
    && jq -e '.isDraft == false and .targetRefName == "refs/heads/main" and .title == "049-x: integration verified"' <<<"$ok_pr" >/dev/null \
    && jq -e '.isDraft == true and (.title | startswith("[draft] "))' <<<"$bad_pr" >/dev/null \
    && grep -q "exit=not-approved-at-ref" <<<"$na_calls" && ! grep -q "^claude -p" <<<"$na_calls"
}
check "R050 AC-5 integrate mode reads the feature's approval, works on specclaw/integrate-<m>, and opens a PR into the target (draft only when the agent fails)" integrate_pod
REMOTE_BRANCH=specclaw/049-x ENTRY_MERGE=feature/cat run_entry; merged="$(cat "$CALLS")"
REMOTE_BRANCH=specclaw/049-x ENTRY_MERGE=feature/cat MERGE_CONFLICT=1 run_entry; conflicted="$(cat "$CALLS")"
REMOTE_BRANCH=specclaw/049-x ENTRY_MERGE=feature/cat FETCH_FAIL=1 run_entry; mfail="$(cat "$CALLS")"
merge_ref() {
  grep -q "merge -q --no-edit origin/feature/cat" <<<"$merged" && grep -q "^claude -p Run the specclaw lifecycle" <<<"$merged" \
    && grep -q "^claude -p The change branch has unresolved merge conflicts with feature/cat" <<<"$conflicted" \
    && grep -q "exit=resume-failed\|exit=merge-ref-failed" <<<"$mfail" && ! grep -q "^claude -p" <<<"$mfail"
}
check "R050 AC-5 FLEET_MERGE_REF merges the feature branch into the resumed change branch first; conflicts are handed to the agent; a failed fetch stops the run" merge_ref
finish
