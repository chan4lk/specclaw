#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export FLEET_VAULT=kv FLEET_IMAGE=ghcr.io/acme/specclaw-fleet:1 AZDO_ORG=o AZDO_PROJECT=p
stub kubectl '
flag() { [[ -n "${!1:-}" ]]; }
case "$*" in
  *" version -o json"*) flag NO_CLUSTER && exit 1; echo "{\"serverVersion\":{\"gitVersion\":\"v1.36\"}}" ;;
  *" get ns "*) flag NO_NS && exit 1; echo ns ;;
  *serviceaccount/fleet-dispatcher*) flag NO_RBAC && exit 1; echo ok ;;
  *"deploy fleet-egress"*) flag NO_EGRESS && echo 0 || echo 1 ;;
  *"networkpolicy fleet-pods"*) flag NO_NETPOL && exit 1; echo ok ;;
  *"secret fleet-azdo"*) flag PARTIAL_SECRET && echo "{\"data\":{\"AZDO_ORG\":1}}" || echo "{\"data\":{\"AZDO_TOKEN\":1,\"AZDO_ORG\":1,\"AZDO_PROJECT\":1}}" ;;
  *"secret fleet-vault-writer"*) echo "{\"data\":{\"AZURE_TENANT_ID\":1,\"AZURE_CLIENT_ID\":1,\"AZURE_CLIENT_SECRET\":1}}" ;;
esac'
stub az '
case "$*" in
  "keyvault show"*) [[ -n "${NO_VAULT:-}" ]] && exit 1; echo kv ;;
  "pipelines show"*) [[ -n "${NO_PIPELINE:-}" ]] && exit 1; echo 44 ;;
  "devops service-endpoint list"*) echo specclaw-fleet-k3s; [[ -n "${NO_CONN:-}" ]] || echo specclaw-fleet-azure ;;
esac'
stub curl 'case "$*" in *ghcr.io/token*) echo "{\"token\":\"t\"}" ;; *manifests*) [[ -n "${NO_IMAGE:-}" ]] && exit 22; exit 0 ;; esac'

doctor() { "$FLEET" doctor > "$TMP/out" 2>&1; }
doctor; clean_rc=$?; clean="$(cat "$TMP/out")"
all_ok() { (( clean_rc == 0 )) && [[ $(grep -c "^ok " <<<"$clean") == 11 ]] && grep -q "all checks ok" <<<"$clean"; }
check "AC7 a healthy setup reports 11 ok lines and exits 0" all_ok

each_fails=1
for case in "NO_CLUSTER:missing context" "NO_NS:missing namespaces" "NO_RBAC:missing rbac" "NO_EGRESS:wrong egress" \
            "NO_NETPOL:missing netpol" "PARTIAL_SECRET:wrong secret:fleet-azdo: lacks key AZDO_TOKEN" "NO_VAULT:missing vault" \
            "NO_IMAGE:missing image" "NO_PIPELINE:missing pipeline" "NO_CONN:missing service-connections: specclaw-fleet-azure"; do
  env "${case%%:*}=1" "$FLEET" doctor > "$TMP/out" 2>&1 && { each_fails=0; echo "  passed despite ${case%%:*}"; }
  grep -qF "${case#*:}" "$TMP/out" || { each_fails=0; echo "  no line for ${case%%:*}"; }
done
reports_each() { (( each_fails == 1 )); }
check "AC7 each broken item is named with its fix and makes doctor exit non-zero" reports_each

FLEET_IMAGE=registry.example.com/x:1 "$FLEET" doctor > "$TMP/out" 2>&1; skip_rc=$?
skips_other() { (( skip_rc == 0 )) && grep -q "^skip image" "$TMP/out"; }
check "AC7 non-GHCR images are skipped, not failed" skips_other
read_only() { ! grep -Eq " (create|apply|delete|patch|update|set|run|label|taint)( |$)|-X (POST|PUT|PATCH|DELETE)" "$CALLS"; }
check "AC7 doctor made no mutating call across all runs" read_only
finish
