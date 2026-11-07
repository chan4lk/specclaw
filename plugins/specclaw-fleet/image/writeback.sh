#!/usr/bin/env bash
set -uo pipefail

STATUS="${FLEET_STATUS_DIR:-/fleet/status}"
AUTH="${HOME:-/home/agent}/.codex/auth.json"
rc="$(cat "$STATUS/exit" 2>/dev/null || echo 1)"

[[ "$FLEET_AGENT" == codex && -f "$AUTH" ]] || exit "$rc"
[[ "$(sha256sum "$AUTH" | cut -d' ' -f1)" == "$(cat "$STATUS/seed.sha" 2>/dev/null)" ]] && exit "$rc"

fail() {
  echo "ERROR: $1; the assignee must re-run specclaw-fleet login --agent codex" >&2
  exit $(( rc != 0 ? rc : 3 ))
}

jq -e 'type == "object" and length > 0' "$AUTH" >/dev/null 2>&1 \
  || fail "refreshed auth.json is not a non-empty JSON object, so the vault secret was left unchanged"

vault_token() {
  curl -sf -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
    --data-urlencode grant_type=client_credentials --data-urlencode "client_id=$AZURE_CLIENT_ID" \
    --data-urlencode "client_secret=$AZURE_CLIENT_SECRET" --data-urlencode scope=https://vault.azure.net/.default \
    | jq -r '.access_token // empty'
}

token="$(vault_token)"
if [[ -n "$token" ]] && jq -n --rawfile v "$AUTH" '{value: $v}' | curl -sf -X PUT \
    "https://$FLEET_VAULT.vault.azure.net/secrets/$FLEET_SECRET?api-version=7.4" \
    -H "Authorization: Bearer $token" -H "Content-Type: application/json" --data-binary @- >/dev/null; then
  echo "codex credential refreshed in $FLEET_SECRET"
  exit "$rc"
fi
fail "codex credential write-back failed"
