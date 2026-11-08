# shellcheck shell=bash disable=SC2034
parse_status_args() {
  S_JSON=0 S_WATCH=0 S_INTERVAL=20 S_SINCE="" S_CHANGES=()
  while (($#)); do
    case "$1" in
      --json) S_JSON=1 ;;
      --watch) S_WATCH=1; [[ "${2:-}" =~ ^[0-9]+$ ]] && { S_INTERVAL="$2"; shift; } ;;
      --since) need_value "$1" "${2:-}"; S_SINCE="$2"; shift ;;
      -*) die "Unknown flag: $1" ;;
      *) S_CHANGES+=("$1") ;;
    esac
    shift
  done
  if (( ! ${#S_CHANGES[@]} )); then
    local d; for d in "$SPECCLAW_DIR"/changes/*/; do d="$(basename "$d")"; proposal_approved "$d" && S_CHANGES+=("$d"); done
  fi
  (( S_WATCH )) && [[ -z "$S_SINCE" ]] && S_SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  return 0
}

status_job() {
  local jobs name pod
  jobs="$(kc -n "${FLEET_NAMESPACE:-specclaw-fleet}" --request-timeout=10s get jobs -l "specclaw.fleet/change=$(label_value "$1")" -o json 2>/dev/null)" \
    || { echo '{"job":"?","phase":"?","pod":"?"}'; return; }
  name="$(jq -r '[.items[]] | sort_by(.metadata.creationTimestamp) | last | .metadata.name // empty' <<<"$jobs")"
  [[ -n "$name" ]] || { echo '{"job":"-","phase":"-","pod":"-"}'; return; }
  pod="$(kc -n "${FLEET_NAMESPACE:-specclaw-fleet}" --request-timeout=10s get pods -l "job-name=$name" -o jsonpath='{.items[-1:].status.phase}' 2>/dev/null)" || pod="?"
  jq -c --arg n "$name" --arg p "${pod:--}" '[.items[] | select(.metadata.name == $n)][0].status as $s
    | {job: $n, pod: $p, phase: (if ($s.succeeded // 0) > 0 then "complete" elif ($s.failed // 0) > 0 then "failed" elif ($s.active // 0) > 0 then "active" else "pending" end)}' <<<"$jobs"
}

status_row() {
  local c="$1" id wi recs
  id="$(work_item_id "$c")"
  [[ -n "$id" ]] || { jq -nc --arg c "$c" '{change: $c, work_item: null, note: "no work item", terminal: true}'; return; }
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$c" 2>/dev/null)" || wi='{"unreadable":true}'
  recs="$(azdo_issue records "$SPECCLAW_DIR" "$c" 2>/dev/null)" || recs='{"unreadable":true}'
  jq -nc --arg c "$c" --arg id "$id" --arg since "$S_SINCE" --argjson wi "$wi" --argjson r "$recs" --argjson job "$(status_job "$c")" '
    ($wi.fields["System.Tags"] // "" | ascii_downcase | split(";") | map(gsub("^\\s+|\\s+$"; ""))) as $t
    | ([$r.records[]? | select((.at | sub("\\.[0-9]+"; "")) >= $since)] | first) as $rec
    | {change: $c, work_item: $id, state: (if $wi.unreadable then "?" else $wi.fields["System.State"] end),
       assignee: (if $wi.unreadable then "?" else ($wi.fields["System.AssignedTo"].uniqueName // "-") end),
       tags: [("auto", "dispatched", "refused") | select(("fleet:" + .) as $x | $t | index($x))],
       record: (if $r.unreadable then {state: "?"} elif $rec then $rec
         elif ($wi.unreadable | not) and ($t | index("fleet:auto") | not) then {state: "not-opted-in"} else {state: "waiting"} end), cluster: $job}
    | .terminal = ((.record.state | IN("pr_open", "failed", "refused")) or (.tags | index("refused")) or ($wi.unreadable | not) and ((.tags | index("auto")) | not))'
}
