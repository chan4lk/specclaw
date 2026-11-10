#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
S="$TMP/sc"; mkdir -p "$S/changes/002-a" "$TMP/azure-pipelines" "$TMP/repo/.specclaw"
many() { awk -v p="$1" -v n="$2" 'BEGIN { for (i = 1; i <= n; i++) printf p "\n", i }'; }
{ echo variables:; many '  fleetImage: "img-%d"' 30000; } > "$TMP/azure-pipelines/specclaw-fleet.yml"
many '**Feature:** cat-%d' 30000 > "$S/changes/002-a/proposal.md"
many '**Azure Boards Work Item:** [#%d](u)' 30000 > "$S/changes/002-a/status.md"
{ echo git:; many '  branch_prefix: "pre%d/"' 30000; } > "$TMP/repo/.specclaw/config.yaml"
echo "{\"branch\":\"\"}" > "$TMP/state.json"
objs="$(many '{"n":%d}' 30000)"
site() {
  SPECCLAW_DIR="$S" REPO="$TMP/repo" STATE="$TMP/state.json" FLEET_CHANGE=002-a FLEET_MODE=integrate OBJS="$objs" bash -c '
    set -euo pipefail; call="$1"; shift; for l in "$@"; do source "$l"; done; eval "$call"' _ "$@" 2>/dev/null
}
L="$FLEET_ROOT/lib"; rows=1
while IFS='|' read -r name call want libs; do
  # shellcheck disable=SC2086
  got="$(site "$call" $libs)"; rc=$?
  (( rc == 0 )) && [[ "$got" == "$want" ]] || { rows=0; echo "  [$name] rc=$rc got=[${got:0:40}]"; }
done <<ROWS
pipeline_var (doctor-azure)|pipeline_var fleetImage|img-1|$L/common.sh $L/doctor-azure.sh
doc_field (feature-graph)|doc_field "\$SPECCLAW_DIR/changes/002-a/proposal.md" Feature|cat-1|$L/common.sh $L/feature-graph.sh
work_item_id (workitem)|work_item_id 002-a|1|$L/common.sh $L/naming.sh $L/workitem.sh
first_obj (report)|first_obj "\$OBJS"|{"n":1}|$L/common.sh $L/report.sh
change_branch (pod workspace)|change_branch|pre1/integrate-002-a|$FLEET_ROOT/image/workspace.sh
ROWS
first_line_ok() { (( rows == 1 )); }
check "R055 every first-line read (pipeline_var, doc_field, work_item_id, first_obj, change_branch) takes the first of 30000 matching lines under pipefail without SIGPIPE" first_line_ok
finish
