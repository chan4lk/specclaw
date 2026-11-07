#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster

reset_env; dispatch --dry-run; plain="$(cat "$TMP/out")"
reset_env; FLEET_IMAGE_PULL_SECRET=ghcr-pull FLEET_NODE_LABEL=specclaw.fleet/worker=true dispatch --dry-run; rc=$?; extras="$(cat "$TMP/out")"

carries_version() { grep -q 'FLEET_CLAUDE_VERSION, value: "2.1.319"' <<<"$plain"; }
absent_by_default() { ! grep -qE "imagePullSecrets|nodeSelector|tolerations" <<<"$plain"; }
present_when_set() {
  (( rc == 0 )) && grep -q "imagePullSecrets: \[{name: ghcr-pull}\]" <<<"$extras" \
    && grep -q 'nodeSelector: {"specclaw.fleet/worker": "true"}' <<<"$extras" \
    && grep -q 'tolerations: \[{key: "specclaw.fleet/worker", operator: Equal, value: "true", effect: NoSchedule}\]' <<<"$extras" \
    && sed -n '/^kind: Job/,/^---/p' <<<"$extras" | sed '$d' | python3 -c 'import sys,yaml; yaml.safe_load(sys.stdin)'
}
refused_all=1
for bad in "FLEET_CLAUDE_VERSION=" "FLEET_CLAUDE_VERSION=latest" "FLEET_CLAUDE_VERSION=2.1.319;x" \
           "FLEET_IMAGE_PULL_SECRET=Bad_Name" "FLEET_NODE_LABEL=noequals" "FLEET_NODE_LABEL=a=b c"; do
  reset_env; env "$bad" "$FLEET" dispatch "$CHANGE" > "$TMP/out" 2>&1 && refused_all=0
  nothing_applied || refused_all=0
done
refuses() { (( refused_all == 1 )); }
reset_env; FLEET_CLAUDE_VERSION="" FLEET_DEFAULT_AGENT=codex dispatch --dry-run; codex_rc=$?
reset_env; FLEET_CLAUDE_VERSION='1.2.3", injected: "x' FLEET_DEFAULT_AGENT=codex dispatch --dry-run; codex_bad_rc=$?
codex_free() { (( codex_rc == 0 && codex_bad_rc != 0 )); }

check "AC4 the Job carries the pinned claude version" carries_version
check "AC4 pull secret and node pinning are absent by default" absent_by_default
check "AC4 pull secret, nodeSelector and toleration appear when set; Job is valid YAML" present_when_set
check "AC4 missing or invalid version, pull secret or node label is refused before anything is created" refuses
check "AC4 codex jobs need no claude version, but a set one is still validated" codex_free
finish
