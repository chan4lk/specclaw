# shellcheck shell=bash
check_vault() {
  [[ -n "${FLEET_VAULT:-}" ]] || { echo "missing vault: set FLEET_VAULT"; return 1; }
  az keyvault show --name "$FLEET_VAULT" --query name -o tsv >/dev/null 2>&1 && { echo "ok vault: $FLEET_VAULT"; return 0; }
  echo "missing vault: $FLEET_VAULT not reachable with the current az login"; return 1
}

check_image() {
  local image repo tag token
  image="$(default_image)"
  [[ "$image" == ghcr.io/*:* ]] || { echo "skip image: only ghcr.io images are checked (${image:-unset})"; return 2; }
  repo="${image#ghcr.io/}"; tag="${repo##*:}"; repo="${repo%:*}"
  token="$(curl -fsS -m 15 "https://ghcr.io/token?scope=repository:$repo:pull" | jq -r '.token // empty')"
  curl -fsS -m 15 -o /dev/null -I -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://ghcr.io/v2/$repo/manifests/$tag" && { echo "ok image: $image (public pull)"; return 0; }
  echo "missing image: $image is not pullable anonymously (pushed? package public?)"; return 1
}

azdo_args() {
  printf '%s\n' --org "https://dev.azure.com/${AZDO_ORG:-}" --project "${AZDO_PROJECT:-}"
}

check_pipeline() {
  local -a a; mapfile -t a < <(azdo_args)
  az pipelines show --name "${FLEET_PIPELINE:-specclaw-fleet}" "${a[@]}" --query id -o tsv >/dev/null 2>&1 \
    && { echo "ok pipeline: ${FLEET_PIPELINE:-specclaw-fleet}"; return 0; }
  echo "missing pipeline: ${FLEET_PIPELINE:-specclaw-fleet} in ${AZDO_ORG:-?}/${AZDO_PROJECT:-?}"; return 1
}

check_connections() {
  local -a a; mapfile -t a < <(azdo_args)
  local ready name missing=""
  ready="$(az devops service-endpoint list "${a[@]}" --query "[?isReady].name" -o tsv 2>/dev/null)"
  for name in "${FLEET_KUBE_CONNECTION:-specclaw-fleet-k3s}" "${FLEET_AZURE_CONNECTION:-specclaw-fleet-azure}"; do
    grep -qxF "$name" <<<"$ready" || missing+=" $name"
  done
  [[ -z "$missing" ]] && { echo "ok service-connections: ready"; return 0; }
  echo "missing service-connections:$missing"; return 1
}
