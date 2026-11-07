#!/usr/bin/env bash
set -uo pipefail

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/specclaw-azdo-issue"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

mkdir -p "$TMP/stub" "$TMP/sc/changes/049-x"
cat > "$TMP/stub/curl" <<'EOF'
#!/usr/bin/env bash
method="" url="" body=""
while (($#)); do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -d) body="$2"; shift 2 ;;
    -H|--max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s %s %s\n' "$method" "$url" "$body" >> "$CURL_LOG"
echo '{}'
EOF
chmod +x "$TMP/stub/curl"
printf '**Azure Boards Work Item:** [#42](https://x)\n' > "$TMP/sc/changes/049-x/status.md"

run_fields() {
  : > "$TMP/curl.log"
  PATH="$TMP/stub:$PATH" CURL_LOG="$TMP/curl.log" AZDO_TOKEN=t AZDO_ORG=o AZDO_PROJECT=p \
    bash "$BIN" fields "$TMP/sc" 049-x "$@" > "$TMP/out" 2>&1
}

check() {
  if "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); cat "$TMP/out" "$TMP/curl.log"; fi
}

cat > "$TMP/sc/config.yaml" <<'EOF'
azdo:
  fleet_fields:
    agent: Custom.FleetAgent
  fleet_states:
    running: Running
EOF
run_fields agent=codex job=fleet-049-ab state=running
patch_line() { grep "^PATCH .*workitems/42" "$TMP/curl.log"; }
mapped_only() { patch_line | grep -q Custom.FleetAgent && patch_line | grep -q System.State && ! patch_line | grep -q fleet-049-ab; }
one_comment() { [[ $(grep -c "^POST .*comments" "$TMP/curl.log") == 1 ]] && grep "^POST" "$TMP/curl.log" | grep -q "job: fleet-049-ab"; }
check "AC9 mapped keys patched, unmapped skipped" mapped_only
check "AC9 one comment lists every pair" one_comment

printf 'azdo:\n  boards:\n    sync: true\n' > "$TMP/sc/config.yaml"
run_fields agent=claude state=failed
rc=$?
comment_only() { [[ $rc == 0 ]] && ! grep -q "^PATCH" "$TMP/curl.log" && grep -q "^POST .*comments" "$TMP/curl.log"; }
check "AC9 nothing mapped: no PATCH, comment only, exit 0" comment_only

(( fails == 0 )) && echo "All azdo-issue fields tests passed." || echo "$fails failed."
exit $(( fails > 0 ))
