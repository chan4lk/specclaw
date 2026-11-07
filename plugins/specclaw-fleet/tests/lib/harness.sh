# shellcheck shell=bash disable=SC2034
FLEET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLEET="$FLEET_ROOT/bin/specclaw-fleet"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/stub" "$TMP/kv"
export PATH="$TMP/stub:$PATH" CALLS="$TMP/calls.log" KV="$TMP/kv"
: > "$CALLS"
fails=0

stub() {
  { echo '#!/usr/bin/env bash'; echo 'echo "$(basename "$0") $*" >> "$CALLS"'; printf '%s\n' "$2"; } > "$TMP/stub/$1"
  chmod +x "$TMP/stub/$1"
}

check() {
  if "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi
}

finish() {
  exit $(( fails > 0 ))
}

hash_of() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | shasum -a 256 | cut -c1-16
}

stub_az() {
  stub az '
arg() { local f="$1"; shift; while (($#)); do [[ "$1" == "$f" ]] && { echo "$2"; return; }; shift; done; }
name="$(arg --name "$@")"; scope="$(arg --scope "$@")"
case "$1 $2 $3" in
  "keyvault show "*) echo "/vaults/v" ;;
  "keyvault secret show")
    [[ -n "${AZ_FAIL:-}" ]] && { echo "ERROR: (Throttled) Too many requests" >&2; exit 1; }
    [[ -f "$KV/$name" ]] || { echo "ERROR: (SecretNotFound) A secret with name $name was not found" >&2; exit 1; }
    cat "$KV/$name" ;;
  "keyvault secret set")
    if [[ -n "$(arg --file "$@")" ]]; then cp "$(arg --file "$@")" "$KV/$name"; else arg --value "$@" > "$KV/$name"; fi ;;
  "role assignment list") grep -qxF "$(arg --assignee "$@") $scope" "$KV/ra" 2>/dev/null && echo ra-id ;;
  "role assignment create") echo "$(arg --assignee "$@") $scope" >> "$KV/ra" ;;
  "account show "*) echo "$AZ_UPN" ;;
esac'
}
