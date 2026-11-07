#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
K="$FLEET_ROOT/k8s"
P="$FLEET_ROOT/pipelines/dispatch.yml"

rules() { grep -A2 "resources: \[\"$1\"\]" "$K/rbac.yaml" | grep -o 'verbs: .*'; }
role_minimal() {
  [[ "$(rules jobs)" == 'verbs: ["create", "get", "list", "delete"]' && "$(rules secrets)" == 'verbs: ["create"]' ]] \
    && [[ $(grep -c "resources:" "$K/rbac.yaml") == 2 ]]
}
pods_default_deny() {
  grep -A3 "name: fleet-pods" "$K/network-policy.yaml" >/dev/null \
    && [[ $(grep -c "policyTypes: \[Ingress, Egress\]" "$K/network-policy.yaml") == 2 ]] \
    && grep -q "app: fleet-egress}}" "$K/network-policy.yaml"
}
proxy_blocks_internal() {
  grep -q "except: \[.*169.254.0.0/16.*\]" "$K/network-policy.yaml" && grep -q "10.0.0.0/8" "$K/network-policy.yaml"
}
allowlist() {
  local host
  for host in api.anthropic.com api.openai.com auth.openai.com dev.azure.com login.microsoftonline.com .vault.azure.net; do
    grep -q "dstdomain.* $host" "$K/egress-proxy.yaml" || return 1
  done
  grep -q "http_access deny all" "$K/egress-proxy.yaml"
}
pipeline_event_driven() {
  grep -q "specclaw-fleet dispatch" "$P" && ! grep -Eq "sleep|while " "$P" && grep -q "System.AccessToken" "$P"
}

check "AC10 dispatcher Role: jobs create/get/list/delete, secrets create only" role_minimal
check "AC10 fleet pods: default-deny, egress only to DNS and the proxy" pods_default_deny
check "AC10 proxy egress excludes metadata and private ranges" proxy_blocks_internal
check "AC10 proxy allowlist covers the required hosts and denies the rest" allowlist
check "FR10 pipeline dispatches on state change, never polls" pipeline_event_driven
finish
