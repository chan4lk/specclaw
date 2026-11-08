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
  optin) w="$(cat "$d/who")"; [[ -n "$w" && "$w" != "$5" ]] && exit 4; echo "$5" > "$d/who"; echo "$4" > "$d/tags" ;;
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
no_wi() { (( nowi_rc == 1 )) && grep -q "no work item; run: specclaw-fleet trigger 005-d --create" <<<"$nowi_out"; }
no_identity() { (( who_rc == 1 && who_calls == 0 )); }
check "R053 AC-3 optin assigns to the AZDO_TOKEN identity and tags; someone else's item is refused (exit 4) while the rest proceed" self_only
check "R053 AC-3 --dry-run shows the plan, names the other assignee, and writes nothing" dry_writes_nothing
check "R053 AC-3 a change with no work item exits 1 naming --create" no_wi
check "R053 AC-3 an unreadable caller identity stops before any write" no_identity
finish
