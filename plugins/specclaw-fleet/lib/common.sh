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

load_azdo_env() {
  local line key value
  [[ -z "${AZDO_ORG:-}" && -f "$SPECCLAW_DIR/.env" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^(export[[:space:]]+)?(AZDO_ORG|AZDO_PROJECT|AZDO_TOKEN)=(.*)$ ]] || continue
    key="${BASH_REMATCH[2]}" value="${BASH_REMATCH[3]}"
    if [[ "$value" =~ ^\"([^\"]*)\"$ || "$value" =~ ^\'([^\']*)\'$ ]]; then value="${BASH_REMATCH[1]}"
    else value="${value%%[[:space:]]#*}"; fi
    [[ "$value" =~ ^[^[:space:]\"\']*$ ]] || { warn "ignored unparsable $key line in $SPECCLAW_DIR/.env"; continue; }
    export "$key=$value"
  done < "$SPECCLAW_DIR/.env"
}
