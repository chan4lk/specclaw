#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
R="$FLEET_ROOT/skills/run/SKILL.md"; S="$FLEET_ROOT/skills/setup/SKILL.md"; CI="$FLEET_ROOT/../../.github/workflows/ci.yml"
run_skill() {
  grep -q '^description: Use when.*one or more approved specclaw changes' "$R" \
    && grep -q 'specclaw-fleet optin <change>... --dry-run' "$R" && grep -q 'Never assign an item to someone else' "$R" \
    && grep -q 'parallel' "$R" && grep -q -- '--sequential' "$R" && grep -q 'status <change>... --watch 30 --since <that time> --run <change>=<run>' "$R" \
    && ! grep -q 'FLEET_VAULT=<vault>' "$R"
}
setup_skill() { grep -q 'under `fleet:`' "$S" && grep -q 'Never write a secret in `fleet:`' "$S" && grep -q 'write `FLEET_KUBE_CONTEXT` and `KUBECONFIG`.*to the gitignored `.specclaw/.env`' "$S"; }
registered() { grep -q 'run-fleet-tests.sh' "$CI" && grep -q 'run-azdo-issue-optin-tests.sh' "$CI"; }
check "R053 AC-5 run skill: dry-run opt-in of the caller only, parallel trigger with --sequential, watch since trigger, no env prefix" run_skill
check "R053 AC-5 setup skill records confirmed values in fleet: and never a secret" setup_skill
check "R053 AC-5 the fleet and optin suites run in CI" registered
P="$FLEET_ROOT/skills/report/SKILL.md"
report_docs() {
  grep -q '^description: Use when.*fleet build' "$P" && grep -q 'specclaw-fleet report \[<scope>\] --save' "$P" && grep -q '/fleet-pane' "$P" \
    && grep -q 'API-equivalent estimate' "$P" && grep -q '^## Build report and pane' "$FLEET_ROOT/README.md" && grep -q 'run-mod-tests.sh' "$CI" \
    && grep -q 'plugins/specclaw-fleet/tests/run-mod-tests.sh' "$CI"
}
check "R054 AC-6 report skill, README section, and the fleet mod suite in CI" report_docs
finish
