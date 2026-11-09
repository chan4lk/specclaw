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
method=GET body="" wfmt="" url=""
while (($#)); do case "$1" in -X) method="$2"; shift 2 ;; -d) body="$2"; shift 2 ;; -w) wfmt="$2"; shift 2 ;; -H|--max-time|-o) shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
case "$url" in
  *connectionData*) echo '{"authenticatedUser":{"id":"u1","providerDisplayName":"Alice","properties":{"Account":{"$type":"System.String","$value":"alice@contoso.com"}}}}'; exit 0 ;;
  *comments*) cat "$S/comments"; exit 0 ;;
esac
rev="$(cat "$S/rev")"
if [[ "$method" == GET ]]; then
  jq -nc --argjson r "$rev" --arg t "$(cat "$S/tags")" --arg a "$(cat "$S/who")" \
    '{rev: $r, fields: ({"System.Tags": $t} + (if $a == "" then {} else {"System.AssignedTo": {uniqueName: $a}} end))}'; exit 0
fi
echo "$method $body" >> "$S/log"
reply() { [[ -n "$wfmt" ]] && printf '%s' "$1"; [[ "$1" == 2* ]] || exit 22; exit 0; }
if [[ -n "${RACE:-}" && ! -e "$S/raced" ]]; then touch "$S/raced"; echo $((rev + 1)) > "$S/rev"; reply 412; fi
[[ "$(jq -r '.[0].value' <<<"$body")" == "$rev" ]] || reply 412
jq -r '.[1].value' <<<"$body" | tr -d '\n' > "$S/tags"
a="$(jq -r '[.[] | select(.path == "/fields/System.AssignedTo") | .value][0] // empty' <<<"$body")"; [[ -n "$a" ]] && printf '%s' "$a" > "$S/who"
echo $((rev + 1)) > "$S/rev"; reply 200
EOF2
chmod +x "$TMP/stub/curl"
azdo() {
  export S="$TMP/s"; rm -rf "$S" && mkdir -p "$S" && echo 7 > "$S/rev" && printf '%s' "$TAGS" > "$S/tags" && printf '%s' "$WHO" > "$S/who" && : > "$S/log"
  printf '%s' "${COMMENTS:-{\"comments\":[]\}}" > "$S/comments"
  PATH="$TMP/stub:$PATH" AZDO_TOKEN=t AZDO_ORG=o AZDO_PROJECT=p bash "$BIN" "$1" "$TMP/sc" 049-x "${@:2}" > "$TMP/out" 2>&1
}
check() { if "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); cat "$TMP/out"; fi; }
rows=1
row() {
  local tags="$1" who="$2" race="$3" want_rc="$4" want_tags="$5" want_who="$6" want_patches="$7" rc=0
  TAGS="$tags" WHO="$who" RACE="$race" azdo optin fleet:auto alice@contoso.com || rc=$?
  [[ "$rc" == "$want_rc" && "$(cat "$S/tags")" == "$want_tags" && "$(cat "$S/who")" == "$want_who" && "$(grep -c . "$S/log")" == "$want_patches" ]] \
    || { rows=0; echo "  row [$tags|$who|$race]: rc=$rc tags=$(cat "$S/tags") who=$(cat "$S/who") patches=$(grep -c . "$S/log")"; cat "$TMP/out"; }
}
row "specclaw" "" "" 0 "specclaw; fleet:auto" alice@contoso.com 1
row "specclaw" "Alice@Contoso.com" "" 0 "specclaw; fleet:auto" Alice@Contoso.com 1
row "specclaw; fleet:auto" "alice@contoso.com" "" 0 "specclaw; fleet:auto" alice@contoso.com 2
row "specclaw; fleet:auto" "" "" 0 "specclaw; fleet:auto" alice@contoso.com 2
row "specclaw" "bob@contoso.com" "" 4 "specclaw" bob@contoso.com 0
row "specclaw" "" "yes" 0 "specclaw; fleet:auto" alice@contoso.com 2
one_patch() { (( rows == 1 )) && TAGS=specclaw WHO="" RACE="" azdo optin fleet:auto alice@contoso.com \
  && jq -e '.[0].op == "test" and ([.[] | .path] | index("/fields/System.AssignedTo")) and ([.[] | .path] | index("/fields/System.Tags"))' <<<"$(sed 's/^PATCH //' "$S/log")" >/dev/null; }
check "optin assigns and tags in one rev-guarded PATCH; an existing tag is removed then re-added by the caller; someone else's item exits 4 with no write; a race retries" one_patch
TAGS="specclaw" WHO="" RACE="" azdo optin fleet:auto bob@contoso.com; other_rc=$?; other_patches="$(grep -c . "$S/log")"
not_for_others() { (( other_rc != 0 && other_patches == 0 )) && grep -q "only to the AZDO_TOKEN identity (alice@contoso.com), not bob@contoso.com" "$TMP/out"; }
check "optin refuses to assign anyone but the AZDO_TOKEN identity" not_for_others
TAGS="" WHO="" azdo whoami
whoami_ok() { jq -e '.upn == "alice@contoso.com" and .name == "Alice"' "$TMP/out" >/dev/null; }
check "whoami names the identity behind AZDO_TOKEN" whoami_ok
COMMENTS='{"comments":[{"createdDate":"2026-11-08T02:50:00Z","text":"specclaw-fleet run update:<br>- state: running<br>- claude_fetch_s: 20"},{"createdDate":"2026-11-08T03:00:00Z","text":"<div>specclaw-fleet run update:</div><div>- state: pr_open</div><div>- pr: https://x/pr/1</div><div>- draft: true</div>"},{"createdDate":"2026-11-08T03:01:00Z","text":"a human comment"}]}' \
  TAGS="" WHO="" azdo records
records_ok() { jq -e '.work_item == "42" and (.records | length == 2) and .records[0].state == "pr_open" and .records[0].draft == "true" and .records[1].claude_fetch_s == "20"' "$TMP/out" >/dev/null; }
check "records parses fleet run updates (html or br), newest first, ignoring other comments" records_ok
COMMENTS='{"value":[]}' TAGS="" WHO="" azdo records; nolist_rc=$?
records_strict() { (( nolist_rc != 0 )); }
check "records fails on an answer with no comments list, never reports it as no records" records_strict
echo
(( fails == 0 )) && echo "All azdo-issue optin tests passed." || echo "$fails failure(s)."
exit $(( fails > 0 ))
