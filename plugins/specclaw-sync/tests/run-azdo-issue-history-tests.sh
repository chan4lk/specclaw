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
method=GET url="" body=""
while (($#)); do
  case "$1" in -X) method="$2"; shift 2 ;; -d) body="$2"; shift 2 ;; -H|--max-time) shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac
done
printf '%s %s %s\n' "$method" "$url" "$body" >> "$CURL_LOG"
case "$method $url" in
  *"skip=0&"*) python3 -c 'import json; print(json.dumps({"value":[{"id":i} for i in range(200)]}))' ;;
  *"skip=200&"*) [[ -n "${PAGE2_FAIL:-}" ]] && exit 22; echo '{"value":[{"id":200},{"id":201},{"id":202}]}' ;;
  "GET "*) printf '{"fields":{"System.Tags":"%s"}}\n' "$TAGS" ;;
  *) echo '{}' ;;
esac
EOF2
chmod +x "$TMP/stub/curl"

azdo() {
  : > "$TMP/curl.log"
  PATH="$TMP/stub:$PATH" CURL_LOG="$TMP/curl.log" AZDO_TOKEN=t AZDO_ORG=o AZDO_PROJECT=p bash "$BIN" "$1" "$TMP/sc" 049-x "${@:2}" > "$TMP/out" 2>&1
}
check() { if "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); cat "$TMP/out"; fi; }

azdo updates; rc=$?
all_pages() { (( rc == 0 )) && [[ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["value"]))' "$TMP/out")" == 203 ]]; }
check "updates pages through the whole history" all_pages
PAGE2_FAIL=1 azdo updates; rc=$?
partial_fails() { (( rc != 0 )) && grep -q "skip 200" "$TMP/out"; }
check "updates fails instead of returning a partial history" partial_fails

TAGS="specclaw" azdo tag fleet:dispatched; rc=$?
tag_added() { (( rc == 0 )) && grep -q '^PATCH .*"value": "specclaw; fleet:dispatched"' "$TMP/curl.log"; }
check "tag appends to existing tags" tag_added
for existing in "Fleet:Dispatched" "a; fleet:dispatched" "fleet:dispatched ;b"; do
  TAGS="$existing" azdo tag fleet:dispatched; rc=$?
  idempotent() { (( rc == 0 )) && ! grep -q "^PATCH" "$TMP/curl.log"; }
  check "tag is a no-op when '$existing' already holds it" idempotent
done

(( fails == 0 )) && echo "All azdo-issue history tests passed." || echo "$fails failed."
exit $(( fails > 0 ))
