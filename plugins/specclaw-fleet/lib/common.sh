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
