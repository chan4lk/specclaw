#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"
PR_BIN="$FLEET_ROOT/../specclaw-sync/bin/specclaw-azdo-pr"
sed -n '/^pr_target_branch() {/,/^}/p' "$PR_BIN" > "$TMP/prt.sh"
target() { env -u SPECCLAW_PR_TARGET "$@" bash -c 'yaml_val() { [[ -n "${BASE:-}" ]] && echo "$BASE"; }; get_default_branch() { echo "${DEF:-}"; }
  source "$1"; pr_target_branch' _ "$TMP/prt.sh"; }
rows=1
for row in "SPECCLAW_PR_TARGET=feature/catalog BASE=develop|feature/catalog" "BASE=develop|develop" "DEF=trunk|trunk" "X=1|main"; do
  got="$(eval "target ${row%%|*}")"; [[ "$got" == "${row#*|}" ]] || { rows=0; echo "  [${row%%|*}] got $got"; }
done
pr_target() { [[ -s "$TMP/prt.sh" ]] && (( rows == 1 )); }
check "R050 AC-5 specclaw-azdo-pr targets SPECCLAW_PR_TARGET over git.base_branch, then the default branch, then main" pr_target
ENTRY_REF=feature/catalog AGENT_RC=5 run_entry; child="$(cat "$TMP/prtarget")"; child_pr="$(jq -r .targetRefName "$TMP/pr-body.json" 2>/dev/null)"
ENTRY_REF=feature/catalog ENTRY_PR_TARGET=main run_entry; integ="$(cat "$TMP/prtarget")"
run_entry; plain="$(cat "$TMP/prtarget")"
pod_target() { [[ "$child" == feature/catalog && "$child_pr" == refs/heads/feature/catalog && "$integ" == main && "$plain" == main ]]; }
check "R050 AC-5 a pod dispatched from feature/<m> opens its PR (real or draft) into feature/<m>; FLEET_PR_TARGET overrides" pod_target
finish
