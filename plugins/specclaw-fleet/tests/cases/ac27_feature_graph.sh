#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export SPECCLAW_DIR="$TMP/repo/.specclaw"
mk() {
  local c="$1" doc="$2"; shift 2
  mkdir -p "$SPECCLAW_DIR/changes/$c"; printf '# %s\n\n' "$c" > "$SPECCLAW_DIR/changes/$c/$doc"
  printf '%s\n' "$@" >> "$SPECCLAW_DIR/changes/$c/$doc"
}
reset() { rm -rf "$TMP/repo"; mkdir -p "$SPECCLAW_DIR/changes"; }
plan() { (cd "$TMP/repo" && "$FLEET" feature plan "$@") > "$TMP/out" 2>&1; }
reset
mk 002-a proposal.md '**Feature:** catalog' '**Depends on:** none'
mk 003-b proposal.md '**Feature:** catalog' '**Depends on:** 002-a'
mk 004-c proposal.md '**Feature:** catalog' '**Depends on:** 002-a  '
mk 005-d change.md '**Feature:** catalog' '**Depends on:** 003-b, 004-c'
mk 006-x proposal.md '**Feature:** other'
mk 007-y proposal.md 'no feature line'
plan catalog --json; j="$(cat "$TMP/out")"
waves_ok() {
  jq -e '.feature == "catalog" and ([.members[] | "\(.wave):\(.change)"] == ["1:002-a","2:003-b","2:004-c","3:005-d"])
    and (.members[3].depends_on == ["003-b","004-c"]) and (.members[0].depends_on == [])' <<<"$j" >/dev/null
}
check "R050 AC-1 members come from **Feature:** in proposal.md or a lean change.md; waves follow **Depends on:** in topological order" waves_ok
err_rows=1
erow() { reset; eval "$1"; plan "$2"; local rc=$?; (( rc != 0 )) && grep -q "$3" "$TMP/out" || { err_rows=0; echo "  [$2] rc=$rc: $(cat "$TMP/out")"; }; }
erow "mk 002-a proposal.md '**Feature:** f' '**Depends on:** 099-missing'" f "002-a depends on 099-missing, which is not a member of feature f"
erow "mk 002-a proposal.md '**Feature:** f' '**Depends on:** 006-x'; mk 006-x proposal.md '**Feature:** g'" f "002-a depends on 006-x, which is not a member of feature f"
erow "mk 002-a proposal.md '**Feature:** f' '**Depends on:** 003-b'; mk 003-b proposal.md '**Feature:** f' '**Depends on:** 002-a'" f "dependency cycle among: 002-a 003-b"
erow "mk 002-a proposal.md '**Feature:** f'" "Bad_Name" "must match"
erow "mk 002-a proposal.md '**Feature:** f'" "nobody" "feature nobody has no members"
errors_named() { (( err_rows == 1 )); }
check "R050 AC-1 an unknown or foreign dependency, a cycle, a bad module name and an empty feature are refused with names" errors_named
reset; mkdir -p "$SPECCLAW_DIR/features/catalog"; printf '**Azure Boards Work Item:** [#300](https://x)\n' > "$SPECCLAW_DIR/features/catalog/status.md"
echo '{"phases":{"proposal":{"status":"approved"}}}' > "$SPECCLAW_DIR/features/catalog/state.json"
item="$(bash -c 'source "$1/lib/common.sh"; source "$1/lib/naming.sh"; source "$1/lib/workitem.sh"; work_item_id catalog; proposal_approved catalog && echo approved' _ "$FLEET_ROOT")"
features_resolve() { [[ "$item" == $'300\napproved' ]]; }
check "R050 a feature under .specclaw/features/<module> resolves like a change (work item, approval)" features_resolve
finish
