#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster

reset_env; dispatch --dry-run; plain="$(cat "$TMP/out")"
reset_env; FLEET_IMAGE_PULL_SECRET=ghcr-pull FLEET_NODE_LABEL=specclaw.fleet/worker=true dispatch --dry-run; rc=$?; extras="$(cat "$TMP/out")"

reset_env; FLEET_BUNDLE_CLAIM=fleet-bundles FLEET_NODE_LABEL=specclaw.fleet/worker=true FLEET_PUSH_ATTEMPTS=3 dispatch --dry-run; claim_rc=$?; claimed="$(cat "$TMP/out")"
reset_env; FLEET_BUNDLE_CLAIM=fleet-bundles dispatch --dry-run; unpinned_rc=$?; unpinned="$(cat "$TMP/out")"

carries_version() { grep -q 'FLEET_CLAUDE_VERSION, value: "2.1.319"' <<<"$plain"; }
absent_by_default() { ! grep -qE "imagePullSecrets|nodeSelector|tolerations" <<<"$plain"; }
present_when_set() {
  (( rc == 0 )) && grep -q "imagePullSecrets: \[{name: ghcr-pull}\]" <<<"$extras" \
    && grep -q 'nodeSelector: {"specclaw.fleet/worker": "true"}' <<<"$extras" \
    && grep -q 'tolerations: \[{key: "specclaw.fleet/worker", operator: Equal, value: "true", effect: NoSchedule}\]' <<<"$extras" \
    && sed -n '/^kind: Job/,/^---/p' <<<"$extras" | sed '$d' | python3 -c 'import sys,yaml; yaml.safe_load(sys.stdin)'
}
claim_absent_by_default() { ! grep -qE "bundles|persistentVolumeClaim|subPath|FLEET_PUSH_ATTEMPTS" <<<"$plain"; }
claim_present_when_set() {
  local agent writeback
  agent="$(sed -n '/- name: agent/,/- name: writeback/p' <<<"$claimed")" writeback="$(sed -n '/- name: writeback/,/volumes:/p' <<<"$claimed")"
  (( claim_rc == 0 )) && grep -q '{name: bundles, persistentVolumeClaim: {claimName: fleet-bundles}}' <<<"$claimed" \
    && grep -q '{name: bundles, mountPath: /fleet/bundles, subPath: "o/p/r/049-x"}' <<<"$agent" \
    && ! grep -q bundles <<<"$writeback" && grep -q 'fsGroup: 1000' <<<"$claimed" \
    && grep -q 'FLEET_PUSH_ATTEMPTS, value: "3"' <<<"$agent" \
    && sed -n '/^kind: Job/,/^---/p' <<<"$claimed" | sed '$d' | python3 -c 'import sys,yaml; yaml.safe_load(sys.stdin)'
}
claim_needs_node_label() { (( unpinned_rc != 0 )) && grep -q bundle_claim <<<"$unpinned" && grep -q node_label <<<"$unpinned"; }
refused_all=1
for bad in "FLEET_CLAUDE_VERSION=" "FLEET_CLAUDE_VERSION=latest" "FLEET_CLAUDE_VERSION=2.1.319;x" \
           "FLEET_IMAGE_PULL_SECRET=Bad_Name" "FLEET_NODE_LABEL=noequals" "FLEET_NODE_LABEL=a=b c" \
           "FLEET_DISPATCH_COMMIT=abc" "FLEET_REPO_URL=file:///tmp/r" "FLEET_REPO_URL=https://u:p@h/r" \
           "FLEET_BUNDLE_CLAIM=Bad_Claim" "FLEET_BUNDLE_CLAIM=-x" "FLEET_PUSH_ATTEMPTS=0" "FLEET_PUSH_ATTEMPTS=10" "FLEET_PUSH_ATTEMPTS=x"; do
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
check "AC5 bundle claim and push attempts are absent by default" claim_absent_by_default
check "AC5 claim volume, agent-only mount with org/project/repo/change subPath, fsGroup and push attempts when set" claim_present_when_set
check "AC6 bundle_claim without node_label is refused, naming both settings" claim_needs_node_label
check "AC4 missing or invalid version, pull secret, node label, bundle claim or push attempts is refused before anything is created" refuses
check "AC4 codex jobs need no claude version, but a set one is still validated" codex_free
finish
