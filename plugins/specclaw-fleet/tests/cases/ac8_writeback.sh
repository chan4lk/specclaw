#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
WB="$FLEET_ROOT/image/writeback.sh"
stub curl 'case "$*" in *oauth2*) echo "{\"access_token\":\"tk\"}" ;; *"-X PUT"*) cat > "$TMP/put.body" ;; esac'
export TMP

run_wb() {
  local agent="$1" status="$2" auth="$3"
  rm -rf "${TMP:?}/codex" "${TMP:?}/status" "${TMP:?}/put.body"
  mkdir -p "$TMP/codex" "$TMP/status"
  : > "$CALLS"
  echo "$status" > "$TMP/status/exit"
  printf 'seed' > "$TMP/codex/auth.json"
  sha256sum "$TMP/codex/auth.json" | cut -d' ' -f1 > "$TMP/status/seed.sha"
  if [[ "$auth" == @* ]]; then rm "$TMP/codex/auth.json"; ln -s "${auth#@}" "$TMP/codex/auth.json"
  else printf '%s' "$auth" > "$TMP/codex/auth.json"; fi
  env FLEET_STATUS_DIR="$TMP/status" FLEET_CODEX_HOME="$TMP/codex" FLEET_AGENT="$agent" FLEET_VAULT=v \
    FLEET_SECRET=codex-auth-abc AZURE_TENANT_ID=t AZURE_CLIENT_ID=c AZURE_CLIENT_SECRET=s bash "$WB" > "$TMP/out" 2>&1
}

NEW='{"tokens":{"refresh_token":"r2"}}'
changed_put() {
  run_wb codex 0 "$NEW" && grep -q "v.vault.azure.net/secrets/codex-auth-abc" "$CALLS" && ! grep -q "^curl [^-]" "$CALLS" \
    && [[ $(grep -c "^curl -q " "$CALLS") == 2 ]] \
    && jq -e --arg v "$NEW" '.value == $v' "$TMP/put.body" >/dev/null
}
unchanged_skipped() { run_wb codex 0 seed && ! grep -q "X PUT" "$CALLS"; }
claude_skipped() { run_wb claude 7 "$NEW"; (( $? == 7 )) && ! grep -q curl "$CALLS"; }
keeps_agent_status() { run_wb codex 4 "$NEW"; (( $? == 4 )) && [[ -f "$TMP/put.body" ]]; }
invalid_kept() {
  local bad
  printf '%s' "$NEW" > "$TMP/elsewhere.json"
  for bad in '{"tokens":{"refr' '{}' '' '[1]' '{"tokens":{}}' "@$TMP/elsewhere.json" "@/proc/self/environ"; do
    run_wb codex 0 "$bad"
    (( $? == 3 )) && ! grep -q "X PUT" "$CALLS" || return 1
  done
}

check "AC8 changed auth.json is written back to the assignee's secret" changed_put
check "AC8 unchanged auth.json is not written" unchanged_skipped
check "AC8 claude runs skip write-back and keep the agent's status" claude_skipped
check "AC8 write-back exits with the agent's recorded status" keeps_agent_status
injected_status() {
  local payload
  for payload in 'a[$(touch "$TMP/pwned")]' '1+1' '' 'x' '9999'; do
    run_wb claude "$payload" seed
    (( $? == 1 )) && [[ ! -e "$TMP/pwned" ]] || return 1
  done
}
check "AC8 agent-written exit status is validated, never evaluated" injected_status
check "AC8 truncated, empty, non-object, token-less or symlinked auth.json never overwrites the vault" invalid_kept
finish
