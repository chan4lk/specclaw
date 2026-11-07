# shellcheck shell=bash disable=SC2034
fleet_doctor() {
  D_NS="${FLEET_NAMESPACE:-specclaw-fleet}"
  local failed=0 rc line
  local -a checks=(check_context check_namespaces check_rbac check_egress check_netpol
    "check_secret fleet-azdo AZDO_TOKEN AZDO_ORG AZDO_PROJECT"
    "check_secret fleet-vault-writer AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET"
    check_vault check_image check_pipeline check_connections)
  for line in "${checks[@]}"; do
    rc=0
    read -ra cmd <<<"$line"
    "${cmd[@]}" || rc=$?
    (( rc == 1 )) && failed=$((failed + 1))
  done
  (( failed == 0 )) && echo "doctor: all checks ok" || echo "doctor: $failed check(s) need attention"
  (( failed == 0 ))
}
