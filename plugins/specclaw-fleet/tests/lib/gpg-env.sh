# shellcheck shell=bash disable=SC2034
export GNUPGHOME="$TMP/gnupg"
mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
trap 'gpgconf --kill all >/dev/null 2>&1; rm -rf "$TMP"' EXIT
gpg --batch --quiet --passphrase '' --quick-gen-key "fleet test <t@t>" ed25519 sign never 2>/dev/null
gpg --batch --quiet --passphrase '' --quick-gen-key "impostor <i@t>" ed25519 sign never 2>/dev/null
TEST_FPR="$(gpg --batch --with-colons --fingerprint "fleet test" | awk -F: '/^fpr/{print $10; exit}')"
gpg --batch --armor --export "fleet test" > "$TMP/test-key.asc"
export FLEET_CLAUDE_KEY="$TMP/test-key.asc" FLEET_CLAUDE_FPR="$TEST_FPR"
export FLEET_CLAUDE_RELEASES=https://releases.test FLEET_CLAUDE_VERSION=9.9.9

make_release() {
  local body="$1" mode="${2:-ok}" dir="$TMP/releases/9.9.9" sum size signer="fleet test"
  rm -rf "$dir" && mkdir -p "$dir/linux-x64" "$dir/linux-arm64"
  printf '%s' "$body" | tee "$dir/linux-x64/claude" > "$dir/linux-arm64/claude"
  sum="$(sha256sum "$dir/linux-x64/claude" | cut -d' ' -f1)"
  size="$(wc -c < "$dir/linux-x64/claude" | tr -d ' ')"
  [[ "$mode" == badsum ]] && sum="$(printf x | sha256sum | cut -d' ' -f1)"
  [[ "$mode" == badsize ]] && size=$((size + 1))
  [[ "$mode" == impostor ]] && signer="impostor"
  jq -n --arg s "$sum" --argjson z "$size" '{version: "9.9.9", platforms: {"linux-x64": {binary: "claude", checksum: $s, size: $z}, "linux-arm64": {binary: "claude", checksum: $s, size: $z}}}' \
    > "$dir/manifest.json"
  [[ "$mode" == rollback ]] && jq '.version = "9.9.8"' "$dir/manifest.json" > "$dir/m" && mv "$dir/m" "$dir/manifest.json"
  [[ "$mode" == noplat ]] && jq '.platforms = {"win32-x64": .platforms["linux-x64"]}' "$dir/manifest.json" > "$dir/m" && mv "$dir/m" "$dir/manifest.json"
  gpg --batch --yes --quiet --local-user "$signer" --detach-sign -o "$dir/manifest.json.sig" "$dir/manifest.json"
  [[ "$mode" == tampered ]] && printf ' ' >> "$dir/manifest.json"
  return 0
}
