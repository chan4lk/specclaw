#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
WB="$FLEET_ROOT/image/writeback.sh"
stub curl 'case "$*" in *oauth2*) echo "{\"access_token\":\"tk\"}" ;; *"-X PUT"*) cat > "$TMP/put.body" ;; esac'
export TMP

run_wb() {
  local agent="$1" status="$2" auth="$3"
  rm -rf "${TMP:?}/home" "${TMP:?}/status" "${TMP:?}/put.body"
  mkdir -p "$TMP/home/.codex" "$TMP/status"
  : > "$CALLS"
  echo "$status" > "$TMP/status/exit"
  printf 'seed' > "$TMP/home/.codex/auth.json"
  sha256sum "$TMP/home/.codex/auth.json" | cut -d' ' -f1 > "$TMP/status/seed.sha"
  printf '%s' "$auth" > "$TMP/home/.codex/auth.json"
  env FLEET_STATUS_DIR="$TMP/status" HOME="$TMP/home" FLEET_AGENT="$agent" FLEET_VAULT=v \
    FLEET_SECRET=codex-auth-abc AZURE_TENANT_ID=t AZURE_CLIENT_ID=c AZURE_CLIENT_SECRET=s bash "$WB" > "$TMP/out" 2>&1
}

changed_put() {
  run_wb codex 0 refreshed && grep -q "v.vault.azure.net/secrets/codex-auth-abc" "$CALLS" \
    && jq -e '.value == "refreshed"' "$TMP/put.body" >/dev/null
}
unchanged_skipped() { run_wb codex 0 seed && ! grep -q "X PUT" "$CALLS"; }
claude_skipped() { run_wb claude 7 refreshed; (( $? == 7 )) && ! grep -q curl "$CALLS"; }
keeps_agent_status() { run_wb codex 4 refreshed; (( $? == 4 )) && [[ -f "$TMP/put.body" ]]; }

check "AC8 changed auth.json is written back to the assignee's secret" changed_put
check "AC8 unchanged auth.json is not written" unchanged_skipped
check "AC8 claude runs skip write-back and keep the agent's status" claude_skipped
check "AC8 write-back exits with the agent's recorded status" keeps_agent_status
finish
