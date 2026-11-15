#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
stopped_deadline() { (( rc != 0 )) && nothing_applied && grep -q "FLEET_DEADLINE_MINUTES must be" "$TMP/out"; }
ran() { (( rc == 0 )); }

for minutes in abc -5 1.5 0 1441 99999; do
  reset_env; FLEET_DEADLINE_MINUTES="$minutes" dispatch; rc=$?
  check "AC11 FLEET_DEADLINE_MINUTES '$minutes' refused" stopped_deadline
done
reset_env; FLEET_DEADLINE_MINUTES="" dispatch; rc=$?
check "AC11 empty FLEET_DEADLINE_MINUTES falls back to 120" ran

reset_env
FLEET_NAMESPACE=team-a FLEET_IMAGE=reg/fleet:7 FLEET_DEFAULT_AGENT=codex dispatch --dry-run; rc=$?
settings_from_env() {
  (( rc == 0 )) && grep -q "namespace: team-a" "$TMP/out" && grep -q "image: reg/fleet:7" "$TMP/out" \
    && grep -q "specclaw.fleet/agent: codex" "$TMP/out"
}
check "AC11 fleet settings come from the environment" settings_from_env
reset_env; FLEET_VAULT="" dispatch; rc=$?
no_vault() { (( rc != 0 )) && grep -q "No Key Vault" "$TMP/out" && nothing_applied; }
check "AC11 no vault configured stops dispatch" no_vault
invalid() { (( rc != 0 )) && nothing_applied && grep -q "not a valid" "$TMP/out"; }
for bad in "FLEET_IMAGE=reg/x:1
    hostNetwork: true" "FLEET_IMAGE=a b" "FLEET_NAMESPACE=Team_A" "FLEET_NAMESPACE=a;b" "FLEET_REF=../main" "FLEET_REF=-x"; do
  reset_env; env "$bad" "$FLEET" dispatch "$CHANGE" > "$TMP/out" 2>&1; rc=$?
  check "AC11 injected setting refused: ${bad%%$'\n'*}" invalid
done
reset_env; rm "$SPECCLAW_DIR/config.yaml"; dispatch; rc=$?
no_config() { (( rc != 0 )) && nothing_applied && grep -q "Cannot read" "$TMP/out"; }
check "AC11 missing config.yaml stops dispatch" no_config
reset_env; printf 'github:\n  token: s3cret\nazdo:  # boards\n  fleet_states:\n    failed: Failed\n' > "$SPECCLAW_DIR/config.yaml"
dispatch --dry-run; rc=$?
azdo_only() { (( rc == 0 )) && grep -q 'FLEET_AZDO_CONFIG, value: "azdo:.*failed: Failed' "$TMP/out" && ! grep -q s3cret "$TMP/out"; }
check "AC11 only the azdo block reaches the Job" azdo_only
finish
