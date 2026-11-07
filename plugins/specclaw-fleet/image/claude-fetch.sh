# shellcheck shell=bash disable=SC2034
CLAUDE_RELEASE_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

claude_platform() {
  case "$(uname -m)" in
    x86_64|amd64) echo linux-x64 ;;
    aarch64|arm64) echo linux-arm64 ;;
    *) return 1 ;;
  esac
}

verify_manifest() {
  local gnupg rc=1
  gnupg="$(mktemp -d)" || return 1
  if gpg --homedir "$gnupg" --batch --quiet --import "${FLEET_CLAUDE_KEY:-/opt/fleet/claude-release.asc}" 2>/dev/null \
    && gpg --homedir "$gnupg" --batch --status-fd 1 --verify "$1/manifest.json.sig" "$1/manifest.json" 2>/dev/null \
      | grep -q "^\[GNUPG:\] VALIDSIG ${FLEET_CLAUDE_FPR:-$CLAUDE_RELEASE_FPR} "; then
    rc=0
  fi
  gpgconf --homedir "$gnupg" --kill all >/dev/null 2>&1
  rm -rf "$gnupg"
  return "$rc"
}

fetch_claude() {
  local base="${FLEET_CLAUDE_RELEASES:-https://downloads.claude.ai/claude-code-releases}/${FLEET_CLAUDE_VERSION:-}"
  local dir="$HOME/.fleet/fetch" bin="$HOME/.fleet/bin" plat sum size start
  [[ "${FLEET_CLAUDE_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  start="$(date +%s)"
  rm -rf "$dir" && mkdir -p "$dir" "$bin"
  plat="$(claude_platform)" || return 1
  curl -fsS -m 60 -o "$dir/manifest.json" "$base/manifest.json" || return 1
  curl -fsS -m 60 -o "$dir/manifest.json.sig" "$base/manifest.json.sig" || return 1
  verify_manifest "$dir" || return 1
  sum="$(jq -r --arg p "$plat" '.platforms[$p].checksum // empty' "$dir/manifest.json")"
  size="$(jq -r --arg p "$plat" '.platforms[$p].size // empty' "$dir/manifest.json")"
  [[ -n "$sum" && -n "$size" ]] || return 1
  curl -fsS -m 900 -o "$bin/claude.part" "$base/$plat/claude" || return 1
  if [[ "$(sha256sum "$bin/claude.part" | cut -d' ' -f1)" != "$sum" || "$(wc -c < "$bin/claude.part" | tr -d ' ')" != "$size" ]]; then
    rm -f "$bin/claude.part"
    return 1
  fi
  chmod 755 "$bin/claude.part" && mv "$bin/claude.part" "$bin/claude"
  FLEET_CLAUDE_FETCH_S=$(( $(date +%s) - start ))
}
