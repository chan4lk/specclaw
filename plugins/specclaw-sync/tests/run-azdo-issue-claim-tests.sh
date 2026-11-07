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
method=GET body="" wfmt=""
while (($#)); do case "$1" in -X) method="$2"; shift 2 ;; -d) body="$2"; shift 2 ;; -w) wfmt="$2"; shift 2 ;; -H|--max-time|-o) shift 2 ;; *) shift ;; esac; done
rev="$(cat "$S/rev")"
if [[ "$method" == GET ]]; then printf '{"rev":%s,"fields":{"System.Tags":"%s"}}\n' "$rev" "$(cat "$S/tags")"; exit 0; fi
echo "$method $body" >> "$S/log"
reply() { [[ -n "$wfmt" ]] && printf '%s' "$1"; [[ "$1" == 2* ]] || exit "${2:-22}"; exit 0; }
[[ -n "${FAIL_503:-}" ]] && reply 503
[[ -n "${FAIL_401:-}" ]] && reply 401
if [[ -n "${RACE:-}" && ! -e "$S/raced" ]]; then
  touch "$S/raced"; echo $((rev + 1)) > "$S/rev"; [[ "$RACE" == unrelated ]] || printf '%s' "$RACE" > "$S/tags"; reply 412
fi
[[ "$(jq -r '.[0].value' <<<"$body")" == "$rev" ]] || reply 412
jq -r '.[1].value' <<<"$body" | tr -d '\n' > "$S/tags"; echo $((rev + 1)) > "$S/rev"
[[ -n "${LOST_RESPONSE:-}" ]] && reply 000 28
reply 200
EOF2
chmod +x "$TMP/stub/curl"

azdo() {
  export S="$TMP/s"; rm -rf "$S" && mkdir -p "$S" && echo 7 > "$S/rev" && printf '%s' "$TAGS" > "$S/tags" && : > "$S/log"
  PATH="$TMP/stub:$PATH" AZDO_TOKEN=t AZDO_ORG=o AZDO_PROJECT=p bash "$BIN" "$1" "$TMP/sc" 049-x "${@:2}" > "$TMP/out" 2>&1
}
check() { if "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); cat "$TMP/out"; fi; }
tags_now() { cat "$S/tags"; }
patches() { grep -c . "$S/log"; }

TAGS="specclaw" azdo claim fleet:dispatched fleet:refused; rc=$?
claimed() { (( rc == 0 )) && [[ "$(tags_now)" == "specclaw; fleet:dispatched" ]] && grep -q '"op": "test", "path": "/rev", "value": 7' "$S/log"; }
check "claim adds the tag under a rev precondition" claimed
for held in "fleet:dispatched" "a; Fleet:Refused" "FLEET:DISPATCHED;b"; do
  TAGS="$held" azdo claim fleet:dispatched fleet:refused; rc=$?
  blocked() { (( rc == 3 )) && [[ "$(patches)" == 0 ]]; }
  check "claim exits 3 and writes nothing when '$held' is held" blocked
done
TAGS="specclaw" RACE=unrelated azdo claim fleet:dispatched fleet:refused; rc=$?
retried() { (( rc == 0 )) && [[ "$(patches)" == 2 && "$(tags_now)" == "specclaw; fleet:dispatched" ]]; }
check "an unrelated concurrent edit is retried, not reported as taken" retried
TAGS="specclaw" RACE="specclaw; fleet:dispatched" azdo claim fleet:dispatched fleet:refused; rc=$?
lost() { (( rc == 3 )) && [[ "$(patches)" == 1 ]]; }
check "a concurrent claim by another dispatcher exits 3" lost
for row in "specclaw|claim fleet:dispatched fleet:refused" "specclaw; fleet:dispatched|untag fleet:dispatched" "specclaw|tag fleet:refused"; do
  cmd="${row#*|}"
  # shellcheck disable=SC2086
  TAGS="${row%%|*}" FAIL_503=1 azdo $cmd; rc=$?
  unknown() { (( rc == 1 )) && grep -q "unknown outcome (HTTP 503)" "$TMP/out"; }
  check "'${cmd%% *}' answered 503 is an unknown outcome: exit 1, never 3" unknown
done
TAGS="specclaw" FAIL_401=1 azdo claim fleet:dispatched fleet:refused; rc=$?
rejected() { (( rc == 1 )) && grep -q "rejected .*HTTP 401.*not a race" "$TMP/out"; }
check "a 4xx rejection with no concurrent edit is an error, never exit 3" rejected
TAGS="specclaw" LOST_RESPONSE=1 azdo claim fleet:dispatched fleet:refused; rc=$?
lost_reply() { (( rc == 1 )) && grep -q "unknown outcome" "$TMP/out"; }
check "an applied PATCH whose reply was lost is reported, never read as taken by someone else" lost_reply
TAGS="a; Fleet:Dispatched; b" azdo untag fleet:dispatched; rc=$?
untagged() { (( rc == 0 )) && [[ "$(tags_now)" == "a; b" ]]; }
check "untag removes the tag case-insensitively and keeps the rest" untagged
TAGS="x; Fleet:Refused" azdo tag fleet:refused; rc=$?
noop() { (( rc == 0 )) && [[ "$(patches)" == 0 ]]; }
check "tag is a no-op when the tag is already held" noop

(( fails == 0 )) && echo "All azdo-issue claim tests passed." || echo "$fails failed."
exit $(( fails > 0 ))
