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
    && grep -q '{name: bundles, mountPath: /fleet/bundles, subPath: "dev.azure.com/o/p/r/049-x"}' <<<"$agent" \
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
# The bundle subPath per repo URL: whole host and every path segment, so repos that collided before differ.
sub_rows=1 subs=""
while IFS='|' read -r url want; do
  # shellcheck disable=SC2034 # bundle_subpath reads F_REPO and F_CHANGE
  got="$(source "$FLEET_ROOT/lib/podspec.sh"; F_REPO="$url" F_CHANGE=049-x; bundle_subpath)"
  [[ "$got" == "$want" && "$got" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+$ && "/$got/" != */./* && "/$got/" != */../* ]] \
    || { sub_rows=0; echo "  $url: got $got, want $want"; }
  [[ "$subs" == *"|$got|"* && "$url" != *@* ]] && { sub_rows=0; echo "  $url: shares $got with another repo"; }; subs+="|$got|"
done <<'ROWS'
https://dev.azure.com/o/p/_git/r|dev.azure.com/o/p/r/049-x
https://O@Dev.Azure.com/o/p/_git/r/|dev.azure.com/o/p/r/049-x
https://acme.visualstudio.com/DefaultCollection/p/_git/r|acme.visualstudio.com/DefaultCollection/p/r/049-x
https://github.com/o/r.git|github.com/o/r/049-x
https://github.example.com/o/r|github.example.com/o/r/049-x
https://git.example.com:8443/o/r|git.example.com_3A8443/o/r/049-x
https://gitlab.com/a/b/c/d|gitlab.com/a/b/c/d/049-x
https://gitlab.com/x/b/c/d|gitlab.com/x/b/c/d/049-x
https://h/o/../r|h/o/_../r/049-x
https://h/o/my%20repo|h/o/my_2520repo/049-x
https://h/o/my repo|h/o/my_20repo/049-x
https://h/o/my_repo|h/o/my_5Frepo/049-x
ROWS
subpaths() { (( sub_rows == 1 )); }
codex_free() { (( codex_rc == 0 && codex_bad_rc != 0 )); }

check "AC4 the Job carries the pinned claude version" carries_version
check "AC4 pull secret and node pinning are absent by default" absent_by_default
check "AC4 pull secret, nodeSelector and toleration appear when set; Job is valid YAML" present_when_set
check "AC5 bundle claim and push attempts are absent by default" claim_absent_by_default
check "AC5 claim volume, agent-only mount with host/url path/change subPath, fsGroup and push attempts when set" claim_present_when_set
check "FR-5 bundle subPath per URL (Azure DevOps, visualstudio.com, GitHub, port, .., percent-encoded): distinct, safe segments" subpaths
check "AC6 bundle_claim without node_label is refused, naming both settings" claim_needs_node_label
check "AC4 missing or invalid version, pull secret, node label, bundle claim or push attempts is refused before anything is created" refuses
check "AC4 codex jobs need no claude version, but a set one is still validated" codex_free
finish
