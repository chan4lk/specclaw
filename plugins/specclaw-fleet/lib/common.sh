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

CFG_PY='
import re, sys
mode, path, name = sys.argv[1], sys.argv[2], sys.argv[3]
header = re.compile(r"^([A-Za-z_][\w-]*)\s*:\s*(#.*)?$")
section, key = (name.split(".", 1) + [None])[:2]
current, out = None, []
for line in open(path):
    m = header.match(line)
    if m or re.match(r"^\S", line) and not line.startswith("#"):
        current = m.group(1) if m else None
        if mode == "block" and current == section:
            out.append(line.rstrip("\n"))
        continue
    if current != section:
        continue
    if mode == "block":
        out.append(line.rstrip("\n"))
        continue
    v = re.match(r"^  " + re.escape(key) + r":\s*(.*?)\s*(#.*)?$", line)
    if v:
        out.append(v.group(1).strip("\"\x27"))
        break
print("\n".join(out))
'

cfg_read() {
  [[ -r "$SPECCLAW_DIR/config.yaml" ]] || die "Cannot read $SPECCLAW_DIR/config.yaml"
  python3 -c "$CFG_PY" "$1" "$SPECCLAW_DIR/config.yaml" "$2" || die "Could not parse $SPECCLAW_DIR/config.yaml (python3 is required)"
}

cfg_val() {
  local value
  value="$(cfg_read value "$1")" || exit 1
  printf '%s' "${value:-$2}"
}

cfg_block() {
  cfg_read block "$1" || exit 1
}
