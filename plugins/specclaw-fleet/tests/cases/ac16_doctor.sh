#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export FLEET_VAULT=kv FLEET_IMAGE=ghcr.io/acme/specclaw-fleet:1 AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t FLEET_KUBE_CONNECTION=specclaw-fleet-k3s FLEET_AZURE_CONNECTION=specclaw-fleet-azure
stub kubectl '
flag() { [[ -n "${!1:-}" ]]; }
gone() { flag "$1" && { echo "Error from server (NotFound): $1" >&2; exit 1; }; flag KUBE_FLAKY && { echo "Unable to connect to the server: i/o timeout" >&2; exit 1; }; true; }
case "$*" in
  *" version -o json"*) flag NO_CLUSTER && { echo "error: context \"x\" does not exist" >&2; exit 1; }; flag KUBE_FLAKY && { echo "Unable to connect to the server" >&2; exit 1; }; echo "{\"serverVersion\":{\"gitVersion\":\"v1.36\"}}" ;;
  *" get ns "*) gone NO_NS; echo ns ;;
  *serviceaccount/fleet-dispatcher*) gone NO_RBAC; echo ok ;;
  *"deploy fleet-egress"*) gone NO_EGRESS_DEPLOY; flag NO_EGRESS && echo 0 || echo 1 ;;
  *"networkpolicy fleet-pods"*) gone NO_NETPOL; echo ok ;;
  *"secret fleet-azdo"*) gone NO_SECRET; flag PARTIAL_SECRET && echo "{\"data\":{\"AZDO_ORG\":1}}" || echo "{\"data\":{\"AZDO_TOKEN\":1,\"AZDO_ORG\":1,\"AZDO_PROJECT\":1}}" ;;
  *"secret fleet-vault-writer"*) gone NONE; echo "{\"data\":{\"AZURE_TENANT_ID\":1,\"AZURE_CLIENT_ID\":1,\"AZURE_CLIENT_SECRET\":1}}" ;;
esac'
stub az '
[[ -n "${AZ_DOWN:-}" ]] && { echo "ERROR: Please run az login" >&2; exit 1; }
case "$*" in
  "keyvault list"*) [[ -n "${NO_VAULT:-}" ]] || echo kv ;;
esac'
stub curl 'case "$*" in
  *ghcr.io/token*) [[ -n "${GHCR_DOWN:-}" ]] && exit 7; echo "{\"token\":\"t\"}"; printf %s "${TOKEN_CODE:-200}" ;;
  *manifests*) printf %s "${IMAGE_CODE:-200}" ;;
  *dev.azure.com*) [[ -n "${AZDO_DOWN:-}" ]] && exit 22; [[ -n "${PAT_SCOPE:-}" ]] && { printf "\n401"; exit 0; } ;;&
  *"build/definitions?name=specclaw-fleet"*) [[ -n "${NO_PIPELINE:-}" ]] && echo "{\"value\":[]}" || echo "{\"value\":[{\"id\":44,\"name\":\"specclaw-fleet\"}]}"; printf "\n%s" "${HTTP_CODE:-200}" ;;
  *serviceendpoint*) echo "{\"value\":[{\"name\":\"specclaw-fleet-k3s\",\"isReady\":true},{\"name\":\"specclaw-fleet-azure\",\"isReady\":$([[ -n "${NO_CONN:-}" ]] && echo false || echo true)}]}"; printf "\n%s" "${HTTP_CODE:-200}" ;;
esac'

doctor() { "$FLEET" doctor > "$TMP/out" 2>&1; }
doctor; clean_rc=$?; clean="$(cat "$TMP/out")"
all_ok() { (( clean_rc == 0 )) && [[ $(grep -c "^ok " <<<"$clean") == 11 ]] && grep -q "all checks ok" <<<"$clean"; }
check "AC7 a healthy setup reports 11 ok lines and exits 0" all_ok

each_fails=1
for case in "NO_CLUSTER:missing context" "NO_NS:missing namespaces" "NO_RBAC:missing rbac" "NO_EGRESS:wrong egress" \
            "NO_NETPOL:missing netpol" "PARTIAL_SECRET:wrong secret:fleet-azdo: lacks key AZDO_TOKEN" "NO_VAULT:missing vault" \
            "IMAGE_CODE=404:missing image" "TOKEN_CODE=403:package missing or private" "IMAGE_CODE=401:missing image" "NO_SECRET:missing secret:fleet-azdo" "NO_EGRESS_DEPLOY:missing egress" "NO_PIPELINE:missing pipeline" "NO_CONN:missing service-connections: specclaw-fleet-azure"; do
  v="${case%%:*}"; [[ "$v" == *=* ]] || v="$v=1"
  env "$v" "$FLEET" doctor > "$TMP/out" 2>&1 && { each_fails=0; echo "  passed despite ${case%%:*}"; }
  grep -qF "${case#*:}" "$TMP/out" || { each_fails=0; echo "  no line for ${case%%:*}"; }
done
reports_each() { (( each_fails == 1 )); }
check "AC7 each broken item is named with its fix and makes doctor exit non-zero" reports_each

FLEET_IMAGE=registry.example.com/x:1 "$FLEET" doctor > "$TMP/out" 2>&1; skip_rc=$?
skips_other() { (( skip_rc == 2 )) && grep -q "^skip image" "$TMP/out" && grep -q "incomplete, 1 check(s) did not run" "$TMP/out" && ! grep -q "all checks ok" "$TMP/out"; }
check "AC7 a check that did not run makes doctor incomplete (exit 2), never all ok" skips_other
NO_VAULT=1 FLEET_IMAGE=registry.example.com/x:1 "$FLEET" doctor > "$TMP/out" 2>&1; mixed_rc=$?
mixed() { (( mixed_rc == 1 )) && grep -q "1 check(s) need attention, 1 did not run" "$TMP/out"; }
check "AC7 failures plus skips report both and exit 1" mixed
skip_rows=1
for row in "KUBE_FLAKY:context namespaces rbac egress netpol secret:fleet-azdo secret:fleet-vault-writer" "AZ_DOWN:vault" "AZDO_DOWN:pipeline service-connections" "PAT_SCOPE:pipeline service-connections" \
           "GHCR_DOWN:image" "IMAGE_CODE=503:image" "IMAGE_CODE=000:image"; do
  v="${row%%:*}"; [[ "$v" == *=* ]] || v="$v=1"
  env "$v" "$FLEET" doctor > "$TMP/out" 2>&1; rc=$?
  for name in ${row#*:}; do grep -q "^skip $name" "$TMP/out" || { skip_rows=0; echo "  $v: $name not skipped"; }; done
  (( rc == 2 )) && ! grep -Eq "^(missing|wrong) " "$TMP/out" || { skip_rows=0; echo "  $v: rc=$rc or a missing/wrong line"; }
done
PAT_SCOPE=1 "$FLEET" doctor > "$TMP/out" 2>&1
scope_named() { grep -q "skip pipeline: AZDO_TOKEN lacks the Build (Read) scope" "$TMP/out" && grep -q "skip service-connections: AZDO_TOKEN lacks the Service Connections (Read) scope" "$TMP/out"; }
unasked_is_skip() { (( skip_rows == 1 )) && scope_named; }
check "R11 a check that could not ask (network, auth, 5xx) is skip (rc 2), never missing/wrong" unasked_is_skip
read_only() { ! grep -Eq " (create|apply|delete|patch|update|set|run|label|taint)( |$)|-X (POST|PUT|PATCH|DELETE)" "$CALLS"; }
check "AC7 doctor made no mutating call across all runs" read_only
finish
