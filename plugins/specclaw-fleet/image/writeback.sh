#!/usr/bin/env bash
set -uo pipefail

STATUS="${FLEET_STATUS_DIR:-/fleet/status}"
AUTH="${FLEET_CODEX_HOME:-/fleet/codex}/auth.json"
rc="$(head -c 4 "$STATUS/exit" 2>/dev/null | tr -d '\n')"
[[ "$rc" =~ ^[0-9]{1,3}$ ]] || rc=1

fail() {
  echo "ERROR: $1; the assignee must re-run specclaw-fleet login --agent codex" >&2
  exit $(( rc != 0 ? rc : 3 ))
}

[[ "$FLEET_AGENT" == codex && ( -e "$AUTH" || -L "$AUTH" ) ]] || exit "$rc"
[[ -L "$AUTH" || ! -f "$AUTH" ]] && fail "auth.json is not a regular file, so the vault secret was left unchanged"
[[ "$(sha256sum "$AUTH" | cut -d' ' -f1)" == "$(cat "$STATUS/seed.sha" 2>/dev/null)" ]] && exit "$rc"

jq -e 'type == "object" and ((.tokens.refresh_token // "") | length) > 0' "$AUTH" >/dev/null 2>&1 \
  || fail "refreshed auth.json is not a JSON object with tokens.refresh_token, so the vault secret was left unchanged"

vault_token() {
  curl -q -sf -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
    --data-urlencode grant_type=client_credentials --data-urlencode "client_id=$AZURE_CLIENT_ID" \
    --data-urlencode "client_secret=$AZURE_CLIENT_SECRET" --data-urlencode scope=https://vault.azure.net/.default \
    | jq -r '.access_token // empty'
}

token="$(vault_token)"
if [[ -n "$token" ]] && jq -n --rawfile v "$AUTH" '{value: $v}' | curl -q -sf -X PUT \
    "https://$FLEET_VAULT.vault.azure.net/secrets/$FLEET_SECRET?api-version=7.4" \
    -H "Authorization: Bearer $token" -H "Content-Type: application/json" --data-binary @- >/dev/null; then
  echo "codex credential refreshed in $FLEET_SECRET"
  exit "$rc"
fi
echo "ERROR: codex credential write-back failed: check that the writer service principal holds $FLEET_SECRET (specclaw-fleet onboard --writer) and that the vault is reachable" >&2
exit $(( rc != 0 ? rc : 3 ))
