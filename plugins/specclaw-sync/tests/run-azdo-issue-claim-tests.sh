#!/usr/bin/env bash
set -uo pipefail

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/specclaw-azdo-issue"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
mkdir -p "$TMP/stub" "$TMP/sc/changes/049-x"
printf '**Azure Boards Work Item:** [#42](https://x)\n' > "$TMP/sc/changes/049-x/status.md"
cat > "$TMP/stub/curl" <<'EOF2'
#!/usr/bin/env bash
method=GET body=""
while (($#)); do case "$1" in -X) method="$2"; shift 2 ;; -d) body="$2"; shift 2 ;; -H|--max-time) shift 2 ;; *) shift ;; esac; done
printf '%s %s\n' "$method" "$body" >> "$CURL_LOG"
[[ "$method" == PATCH && -n "${PATCH_CONFLICT:-}" ]] && exit 22
[[ "$method" == GET ]] && printf '{"rev":7,"fields":{"System.Tags":"%s"}}\n' "$TAGS"
exit 0
EOF2
chmod +x "$TMP/stub/curl"

azdo() {
  : > "$TMP/curl.log"
  PATH="$TMP/stub:$PATH" CURL_LOG="$TMP/curl.log" AZDO_TOKEN=t AZDO_ORG=o AZDO_PROJECT=p bash "$BIN" "$1" "$TMP/sc" 049-x "${@:2}" > "$TMP/out" 2>&1
}
check() { if "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); cat "$TMP/out"; fi; }

TAGS="specclaw" azdo claim fleet:dispatched fleet:refused; rc=$?
claimed() { (( rc == 0 )) && grep -q '^PATCH .*"op": "test", "path": "/rev", "value": 7' "$TMP/curl.log" && grep -q '"specclaw; fleet:dispatched"' "$TMP/curl.log"; }
check "claim adds the tag under a rev precondition" claimed
for held in "fleet:dispatched" "a; Fleet:Refused" "FLEET:DISPATCHED;b"; do
  TAGS="$held" azdo claim fleet:dispatched fleet:refused; rc=$?
  blocked() { (( rc == 3 )) && ! grep -q "^PATCH" "$TMP/curl.log"; }
  check "claim exits 3 and writes nothing when '$held' is held" blocked
done
TAGS="specclaw" PATCH_CONFLICT=1 azdo claim fleet:dispatched; rc=$?
lost_race() { (( rc == 3 )) && grep -q "changed while claiming" "$TMP/out"; }
check "claim exits 3 when the rev changed in between" lost_race
TAGS="a; Fleet:Dispatched; b" azdo untag fleet:dispatched; rc=$?
untagged() { (( rc == 0 )) && grep -q '^PATCH .*"value": "a; b"' "$TMP/curl.log"; }
check "untag removes the tag case-insensitively and keeps the rest" untagged

(( fails == 0 )) && echo "All azdo-issue claim tests passed." || echo "$fails failed."
exit $(( fails > 0 ))
