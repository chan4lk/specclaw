# shellcheck shell=bash
die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

need_value() {
  [[ -n "${2:-}" && "${2:-}" != -* ]] || die "$1 needs a value"
}

secret_not_found() {
  grep -q '(SecretNotFound)' "$1"
}

sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1
}

upn_hash() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sha256_hex | cut -c1-16
}

secret_name() {
  case "$1" in
    claude) printf 'claude-token-%s' "$2" ;;
    codex) printf 'codex-auth-%s' "$2" ;;
    *) die "Unknown agent '$1' (expected claude or codex)" ;;
  esac
}

kc() {
  kubectl ${FLEET_KUBE_CONTEXT:+--context "$FLEET_KUBE_CONTEXT"} "$@"
}

default_image() {
  printf '%s' "${FLEET_IMAGE:-ghcr.io/chan4lk/specclaw-fleet:$(jq -r .version "$FLEET_ROOT/.claude-plugin/plugin.json")}"
}

https_repo_url() {
  local u
  u="$(git -C "$SPECCLAW_DIR/.." remote get-url "$1")" || die "no git remote '$1'"
  [[ "$u" =~ ^git@ssh\.dev\.azure\.com:v3/([^/]+)/([^/]+)/([^/]+)$ ]] \
    && u="https://dev.azure.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/_git/${BASH_REMATCH[3]}"
  u="$(sed -E 's#://[^@/]+@#://#' <<<"$u")"
  [[ "$u" =~ ^https://[^@[:space:]]+$ ]] || die "remote '$1' is not an https URL ($u); the pod clones over https"
  printf '%s' "$u"
}

load_dotenv() {
  local line key value keys="$*"
  [[ -f "$SPECCLAW_DIR/.env" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^(export[[:space:]]+)?([A-Z_]+)=(.*)$ && " $keys " == *" ${BASH_REMATCH[2]} "* ]] || continue
    key="${BASH_REMATCH[2]}" value="${BASH_REMATCH[3]}"
    [[ -z "${!key+x}" ]] || continue
    if [[ "$value" =~ ^\"([^\"]*)\"$ || "$value" =~ ^\'([^\']*)\'$ ]]; then value="${BASH_REMATCH[1]}"
    else value="${value%%[[:space:]]#*}"; fi
    [[ "$value" =~ ^[^[:space:]\"\']*$ ]] || { warn "ignored unparsable $key line in $SPECCLAW_DIR/.env"; continue; }
    export "$key=$value"
  done < "$SPECCLAW_DIR/.env"
}

load_azdo_env() { load_dotenv AZDO_ORG AZDO_PROJECT AZDO_TOKEN; }

load_local_env() {
  local had="${KUBECONFIG+x}" root
  load_dotenv FLEET_KUBE_CONTEXT KUBECONFIG
  [[ -n "$had" || -z "${KUBECONFIG:-}" || "$KUBECONFIG" == /* || "$KUBECONFIG" == *:* ]] && return 0
  root="$(cd "$SPECCLAW_DIR/.." 2>/dev/null && pwd)" || die "cannot resolve KUBECONFIG from $SPECCLAW_DIR/.env: no repo root"
  export KUBECONFIG="$root/${KUBECONFIG#./}"
}

