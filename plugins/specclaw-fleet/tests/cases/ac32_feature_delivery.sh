#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
yq_py() { python3 -c "import sys,yaml,json; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" "$1"; }
rows=1
for t in dispatch.yml dispatch-hosted.yml; do
  [[ "$(yq_py "$FLEET_ROOT/pipelines/$t" | jq -c '.trigger.branches.include')" == '["main","feature/*"]' ]] || { rows=0; echo "  $t: trigger branches"; }
  for row in "refs/heads/feature/cat|0|specclaw-fleet feature advance cat" "refs/heads/feature/cat|1|specclaw-fleet feature advance cat" "refs/heads/main|0|specclaw-fleet dispatch 049-x"; do
    IFS='|' read -r ref drc want <<<"$row"
    out="$(PIPELINE_FILE="$t" bash -c 'source "$1/tests/lib/harness.sh"; source "$1/tests/lib/pipeline-env.sh"
      export FLEET_REF="$2" DISPATCH_RC="$3"; run_with_state 049-x "$APPROVED"; echo "rc=$?"; grep "^specclaw-fleet" "$CALLS"'  _ "$FLEET_ROOT" "$ref" "$drc")"
    [[ "$out" == *"rc=$drc"* && "$out" == *"$want"* && $(grep -c "^specclaw-fleet" <<<"$out") == 1 ]] || { rows=0; echo "  $t $ref rc=$drc: $out"; }
  done
done
pipelines_ok() { (( rows == 1 )); }
check "R050 AC-6 both templates trigger on main and feature/*; a feature/<m> run runs only feature advance <m> and returns its status; main still scans" pipelines_ok
S="$FLEET_ROOT/skills/feature/SKILL.md"
skill_ok() {
  grep -q '^description: Use when.*several related approved specclaw changes' "$S" && grep -q 'feature init <module>' "$S" \
    && grep -q 'feature start <module>' "$S" && grep -q "Never opt in an item assigned to someone else" "$S" && grep -q 'A failed child blocks only its dependents' "$S"
}
check "R050 AC-6 the feature skill drives plan, init, opt-in, start and watch, and keeps consent with the caller" skill_ok
finish
