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
  local image repo tag token code
  image="$(default_image)"
  [[ "$image" == ghcr.io/*:* ]] || { echo "skip image: only ghcr.io images are checked (${image:-unset})"; return 2; }
  repo="${image#ghcr.io/}"; tag="${repo##*:}"; repo="${repo%:*}"
  token="$(curl -fsS -m 15 "https://ghcr.io/token?scope=repository:$repo:pull" | jq -r '.token // empty')"
  [[ -n "$token" ]] || { echo "skip image: could not get an anonymous ghcr.io token (network?)"; return 2; }
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
  local -a a; mapfile -t a < <(azdo_args)
  local id
  id="$(az pipelines list --name "${FLEET_PIPELINE:-specclaw-fleet}" "${a[@]}" --query "[0].id" -o tsv 2>/dev/null)" \
    || { echo "skip pipeline: could not list pipelines (az devops login? network?)"; return 2; }
  [[ -n "$id" ]] && { echo "ok pipeline: ${FLEET_PIPELINE:-specclaw-fleet}"; return 0; }
  echo "missing pipeline: ${FLEET_PIPELINE:-specclaw-fleet} in ${AZDO_ORG:-?}/${AZDO_PROJECT:-?}"; return 1
}

check_connections() {
  local -a a; mapfile -t a < <(azdo_args)
  local ready name missing=""
  ready="$(az devops service-endpoint list "${a[@]}" --query "[?isReady].name" -o tsv 2>/dev/null)" \
    || { echo "skip service-connections: could not list them (az devops login? network?)"; return 2; }
  for name in "${FLEET_KUBE_CONNECTION:-specclaw-fleet-k3s}" "${FLEET_AZURE_CONNECTION:-specclaw-fleet-azure}"; do
    grep -qxF "$name" <<<"$ready" || missing+=" $name"
  done
  [[ -z "$missing" ]] && { echo "ok service-connections: ready"; return 0; }
  echo "missing service-connections:$missing"; return 1
}
