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

cfg_val() {
  local value
  value="$(python3 - "$SPECCLAW_DIR/config.yaml" "$1" <<'PY'
import os, re, sys
path, (section, key) = sys.argv[1], sys.argv[2].split(".", 1)
if not os.path.exists(path):
    sys.exit(0)
current = None
for line in open(path):
    if re.match(r"^[A-Za-z_]", line):
        current = line.split(":", 1)[0].strip()
    elif current == section:
        m = re.match(r"^  " + re.escape(key) + r":\s*(.*?)\s*(#.*)?$", line)
        if m:
            print(m.group(1).strip("\"'"))
            break
PY
)" || die "Could not read $SPECCLAW_DIR/config.yaml (python3 is required)"
  printf '%s' "${value:-$2}"
}

cfg_block() {
  [[ -f "$SPECCLAW_DIR/config.yaml" ]] || return 0
  awk -v head="$1:" '$0 == head { on = 1; print; next } on && /^[^[:space:]#]/ { exit } on { print }' "$SPECCLAW_DIR/config.yaml"
}
