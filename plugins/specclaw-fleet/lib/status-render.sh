# shellcheck shell=bash
status_pipeline() {
  local name="${FLEET_PIPELINE:-specclaw-fleet}" id run
  id="$(azdo_rest "pipelines?api-version=7.1" | jq -r --arg n "$name" '[.value[] | select(.name == $n)][0].id // empty' 2>/dev/null)"
  [[ -n "$id" ]] || { jq -nc --arg n "$name" '{pipeline: $n, run: "?"}'; return; }
  run="$(azdo_rest "pipelines/$id/runs?\$top=1&api-version=7.1" | jq -c '.value[0] // {}' 2>/dev/null)" || run='{}'
  jq -nc --arg n "$name" --argjson r "${run:-{\}}" '{pipeline: $n, run: ($r.id // "?"), status: ($r.state // "?"), result: ($r.result // "-")}'
}

status_print() {
  jq -r '"pipeline \(.pipeline): run \(.run) \(.status // "") \(.result // "")"' <<<"$1"
  jq -r '[.change, (if .work_item then "#" + .work_item else "-" end), (.state // "-"), (.assignee // "-"),
      (if .tags then (.tags | join(",") | if . == "" then "-" else . end) else "-" end),
      (.note // ((.record.state) + (if .record.exit then " exit=" + .record.exit else "" end)
        + (if .record.pr then " pr=" + .record.pr else "" end) + (if .record.draft == "true" then " (draft)" else "" end))),
      (if .cluster then "\(.cluster.job) \(.cluster.phase)/\(.cluster.pod)" else "-" end)] | @tsv' <<<"$2" \
    | awk -F'\t' 'BEGIN { printf "%-34s %-6s %-8s %-28s %-18s %-40s %s\n", "CHANGE", "ITEM", "STATE", "ASSIGNEE", "FLEET TAGS", "LAST RECORD", "CLUSTER" }
      { printf "%-34s %-6s %-8s %-28s %-18s %-40s %s\n", $1, $2, $3, $4, $5, $6, $7 }'
}

fleet_status() {
  parse_status_args "$@"
  load_azdo_env
  local rows head c
  while :; do
    head="$(status_pipeline)"; rows=""
    for c in "${S_CHANGES[@]}"; do rows+="$(status_row "$c")"$'\n'; done
    if (( S_JSON )); then jq -c --argjson h "$head" -s '{pipeline: $h, changes: .}' <<<"$rows"
    else (( S_WATCH )) && echo "--- $(date -u +%H:%M:%SZ)"; status_print "$head" "$rows"; fi
    (( S_WATCH )) || return 0
    jq -e -s 'all(.terminal)' <<<"$rows" >/dev/null && return 0
    sleep "$S_INTERVAL"
  done
}
