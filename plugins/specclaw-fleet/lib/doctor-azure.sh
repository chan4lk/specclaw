# shellcheck shell=bash
check_vault() {
  [[ -n "${FLEET_VAULT:-}" ]] || { echo "missing vault: set FLEET_VAULT"; return 1; }
  local found
  found="$(az keyvault list --query "[?name=='$FLEET_VAULT'].name" -o tsv 2>/dev/null)" \
    || { echo "skip vault: could not list vaults (az login? network?)"; return 2; }
  [[ -n "$found" ]] && { echo "ok vault: $FLEET_VAULT"; return 0; }
  echo "missing vault: no vault $FLEET_VAULT in the current subscription"; return 1
}

check_image() {
  local image repo tag token code out
  image="$(default_image)"
  [[ "$image" == ghcr.io/*:* ]] || { echo "skip image: only ghcr.io images are checked (${image:-unset})"; return 2; }
  repo="${image#ghcr.io/}"; tag="${repo##*:}"; repo="${repo%:*}"
  out="$(curl -sS -m 15 -w '\n%{http_code}' "https://ghcr.io/token?scope=repository:$repo:pull" 2>/dev/null)"
  case "${out##*$'\n'}" in
    401|403) echo "missing image: $image: package missing or private (ghcr.io refused an anonymous token)"; return 1 ;;
    200) token="$(jq -r '.token // empty' <<<"${out%$'\n'*}" 2>/dev/null)" ;;
  esac
  [[ -n "${token:-}" ]] || { echo "skip image: could not get an anonymous ghcr.io token (network?)"; return 2; }
  code="$(curl -sS -m 15 -o /dev/null -w '%{http_code}' -I -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://ghcr.io/v2/$repo/manifests/$tag")"
  case "$code" in
    200) echo "ok image: $image (public pull)"; return 0 ;;
    401|403|404) echo "missing image: $image is not pullable anonymously (HTTP $code: pushed? package public?)"; return 1 ;;
    *) echo "skip image: ghcr.io answered HTTP ${code:-none}"; return 2 ;;
  esac
}

azdo_args() {
  printf '%s\n' --org "https://dev.azure.com/${AZDO_ORG:-}" --project "${AZDO_PROJECT:-}"
}

check_pipeline() {
  local name="${FLEET_PIPELINE:-specclaw-fleet}" out
  out="$(azdo_rest "pipelines?api-version=7.1")" || { echo "skip pipeline: could not list pipelines with AZDO_TOKEN (set in .specclaw/.env?)"; return 2; }
  jq -e '.value | type == "array"' <<<"$out" >/dev/null 2>&1 || { echo "skip pipeline: AzDO answered with something that is not a pipeline list"; return 2; }
  jq -e --arg n "$name" 'any(.value[]; .name == $n)' <<<"$out" >/dev/null && { echo "ok pipeline: $name"; return 0; }
  echo "missing pipeline: $name in ${AZDO_ORG:-?}/${AZDO_PROJECT:-?}"; return 1
}

pipeline_var() {
  local f="${FLEET_PIPELINE_FILE:-azure-pipelines/specclaw-fleet.yml}"
  sed -nE "s/^  $1:[[:space:]]*\"?([^\"#[:space:]]+)\"?.*/\1/p" "$SPECCLAW_DIR/../$f" 2>/dev/null | head -n1
}

check_connections() {
  local k z out missing
  k="${FLEET_KUBE_CONNECTION:-$(pipeline_var fleetKubeConnection)}"; z="${FLEET_AZURE_CONNECTION:-$(pipeline_var fleetAzureConnection)}"
  [[ -n "$k" && -n "$z" ]] || { echo "skip service-connections: no connection names in ${FLEET_PIPELINE_FILE:-azure-pipelines/specclaw-fleet.yml} (set fleet.pipeline_file)"; return 2; }
  out="$(azdo_rest "serviceendpoint/endpoints?endpointNames=$k,$z&api-version=7.1")" \
    || { echo "skip service-connections: could not list them with AZDO_TOKEN (set in .specclaw/.env?)"; return 2; }
  missing="$(jq -er --arg k "$k" --arg z "$z" '.value | if type == "array" then [$k, $z] - [.[] | select(.isReady) | .name] | join(" ") else error("no list") end' <<<"$out" 2>/dev/null)" \
    || { echo "skip service-connections: AzDO answered with something that is not an endpoint list"; return 2; }
  [[ -z "$missing" ]] && { echo "ok service-connections: ready"; return 0; }
  echo "missing service-connections: $missing"; return 1
}
