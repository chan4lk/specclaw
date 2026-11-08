#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export SPECCLAW_DIR="$TMP/repo/.specclaw" FLEET_AZDO_ISSUE="$TMP/stub/specclaw-azdo-issue" AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t WI="$TMP/wi"
stub specclaw-azdo-issue '
d="$WI/$3"
case "$1" in
  whoami) [[ -n "${NO_WHOAMI:-}" ]] && exit 1; echo "{\"upn\":\"alice@contoso.com\"}" ;;
  show) jq -nc --arg w "$(cat "$d/who")" --arg t "$(cat "$d/tags")" "{fields: ({\"System.Tags\": \$t} + (if \$w == \"\" then {} else {\"System.AssignedTo\": {uniqueName: \$w}} end))}" ;;
  updates) [[ -n "${BAD_HISTORY:-}" ]] && { echo "<html>"; exit 0; }; jq -nc --arg by "$(cat "$d/tagger" 2>/dev/null)" "{value: (if \$by == \"\" then [] else [{revisedBy: {uniqueName: \$by}, fields: {\"System.Tags\": {oldValue: \"specclaw\", newValue: \"specclaw; fleet:auto\"}}}] end)}" ;;
  untag) printf specclaw > "$d/tags"; rm -f "$d/tagger" ;;
  optin) w="$(cat "$d/who")"; [[ -n "$w" && "$w" != "$5" ]] && exit 4; echo "$5" > "$d/who"; echo "specclaw; $4" > "$d/tags"; echo "$5" > "$d/tagger" ;;
esac'
mk() {
  mkdir -p "$SPECCLAW_DIR/changes/$1" "$WI/$1"; printf '%s' "$2" > "$WI/$1/who"; printf 'specclaw' > "$WI/$1/tags"
  [[ "$3" == nowi ]] || printf '**Azure Boards Work Item:** [#%s](https://x)\n' "$3" > "$SPECCLAW_DIR/changes/$1/status.md"
}
reset() { rm -rf "$TMP/repo" "$WI"; mk 002-a "" 209; mk 003-b alice@contoso.com 210; mk 004-c bob@contoso.com 211; mk 005-d "" nowi; : > "$CALLS"; }
optin() { (cd "$TMP/repo" && "$FLEET" optin "$@") > "$TMP/out" 2>&1; }
optins() { grep -c "^specclaw-azdo-issue optin" "$CALLS"; }
reset; optin 002-a 003-b; ok_rc=$?; ok_out="$(cat "$TMP/out")"; ok_calls="$(optins)"
reset; optin 002-a 004-c; mixed_rc=$?; mixed_out="$(cat "$TMP/out")"; bob="$(cat "$WI/004-c/who")"
reset; optin 004-c 005-d; err_rc=$?
reset; optin 005-d; nowi_rc=$?; nowi_out="$(cat "$TMP/out")"
reset; optin 002-a 004-c --dry-run; dry_rc=$?; dry_out="$(cat "$TMP/out")"; dry_calls="$(optins)"
reset; NO_WHOAMI=1 optin 002-a; who_rc=$?; who_calls="$(optins)"
self_only() {
  (( ok_rc == 0 && ok_calls == 2 )) && grep -q "002-a: opted in (#209, assigned to alice@contoso.com" <<<"$ok_out" \
    && (( mixed_rc == 4 )) && [[ "$bob" == bob@contoso.com ]] && grep -q "004-c: refused" <<<"$mixed_out" && grep -q "002-a: opted in" <<<"$mixed_out"
}
dry_writes_nothing() {
  (( dry_calls == 0 && dry_rc == 4 )) && grep -q "002-a: would assign to alice@contoso.com and add fleet:auto" <<<"$dry_out" \
    && grep -q "004-c: refused: assigned to bob@contoso.com" <<<"$dry_out"
}
no_wi() { (( err_rc == 1 && nowi_rc == 1 )) && grep -q "no work item; run: specclaw-fleet trigger 005-d --create" <<<"$nowi_out"; }
no_identity() { (( who_rc == 1 && who_calls == 0 )); }
consent_rows=1
crow() {
  reset; printf 'specclaw; fleet:auto' > "$WI/002-a/tags"; printf '%s' "$2" > "$WI/002-a/who"; printf '%s' "$3" > "$WI/002-a/tagger"
  optin 002-a $1; local rc=$? out; out="$(cat "$TMP/out")"
  [[ "$rc" == 0 && "$out" == *"$4"* && "$(grep -c "azdo-issue untag" "$CALLS")" == "$5" ]] || { consent_rows=0; echo "  [$2|$3|$1]: rc=$rc untags=$(grep -c "azdo-issue untag" "$CALLS") $out"; }
  [[ "$1" == --dry-run ]] || [[ "$(cat "$WI/002-a/tagger")" == alice@contoso.com ]] || { consent_rows=0; echo "  [$2|$3]: tagger now $(cat "$WI/002-a/tagger")"; }
}
crow "" alice@contoso.com bob@contoso.com "opted in" 0
crow "" "" bob@contoso.com "opted in" 0
crow "" alice@contoso.com alice@contoso.com "already opted in by alice@contoso.com" 0
crow --dry-run alice@contoso.com bob@contoso.com "re-add fleet:auto as alice@contoso.com (it was not added by the assignee)" 0
reset; printf 'specclaw; fleet:auto' > "$WI/002-a/tags"; printf alice@contoso.com > "$WI/002-a/who"; BAD_HISTORY=1 optin 002-a; hist_rc=$?; hist_writes="$(grep -cE "azdo-issue (optin|untag)" "$CALLS")"
reset; printf 'specclaw; fleet:auto' > "$WI/002-a/tags"; printf alice@contoso.com > "$WI/002-a/who"; echo bob@contoso.com > "$WI/002-a/tagger"; optin 002-a --dry-run
dry_text="$(cat "$TMP/out")"
consent_fixed() { (( consent_rows == 1 && hist_rc == 1 && hist_writes == 0 )) && [[ "$dry_text" == "002-a: would keep the assignment and re-add fleet:auto as alice@contoso.com (it was not added by the assignee)" ]]; }
check "R053 optin re-adds a fleet:auto the assignee did not add (as the caller); one added by the caller is a no-op; unreadable history is an error with no write; exact dry-run text" consent_fixed
check "R053 AC-3 optin assigns to the AZDO_TOKEN identity and tags; someone else's item is refused (exit 4) while the rest proceed" self_only
check "R053 AC-3 --dry-run shows the plan, names the other assignee, and writes nothing" dry_writes_nothing
check "R053 AC-3 a change with no work item exits 1 naming --create, and an error is not hidden behind another change's refusal" no_wi
check "R053 AC-3 an unreadable caller identity stops before any write" no_identity
finish
