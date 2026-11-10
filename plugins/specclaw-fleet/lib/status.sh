# shellcheck shell=bash disable=SC2034
parse_status_args() {
  local dl="${FLEET_DEADLINE_MINUTES:-120}"
  [[ "$dl" =~ ^[1-9][0-9]{0,4}$ ]] || dl=120
  S_JSON=0 S_WATCH=0 S_INTERVAL=20 S_SINCE="" S_CHANGES=() S_TIMEOUT=$(( 10#$dl + 20 )) S_RUNMAP=""
  while (($#)); do
    case "$1" in
      --json) S_JSON=1 ;;
      --watch) S_WATCH=1; [[ "${2:-}" =~ ^[0-9]+$ ]] && { (( 10#$2 >= 5 )) || die "--watch interval must be at least 5 seconds"; S_INTERVAL="$2"; shift; } ;;
      --since) need_value "$1" "${2:-}"; S_SINCE="$2"; shift ;;
      --run) need_value "$1" "${2:-}"; [[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*=[0-9]+$ ]] || die "--run takes <change>=<pipeline run id>"; S_RUNMAP+=" $2"; shift ;;
      --timeout) need_value "$1" "${2:-}"; [[ "$2" =~ ^[1-9][0-9]{0,4}s?$ ]] || die "--timeout takes minutes, or seconds as <n>s"; S_TIMEOUT="$2"; shift ;;
      -*) die "Unknown flag: $1" ;;
      *) S_CHANGES+=("$1") ;;
    esac
    shift
  done
  if (( ! ${#S_CHANGES[@]} )); then
    local d; for d in "$SPECCLAW_DIR"/changes/*/; do d="$(basename "$d")"; proposal_approved "$d" && S_CHANGES+=("$d"); done
  fi
  (( S_WATCH )) && [[ -z "$S_SINCE" ]] && S_SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ -z "$S_SINCE" || "$S_SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "--since must be UTC like 2026-11-08T03:00:00Z"
  return 0
}

status_job() {
  local jobs name pod
  jobs="$(kc -n "${FLEET_NAMESPACE:-specclaw-fleet}" --request-timeout=10s get jobs -l "specclaw.fleet/change=$(label_value "$1")" -o json 2>/dev/null)" \
    || { echo '{"job":"?","phase":"?","pod":"?"}'; return; }
  jq -e '.items | type == "array" and all(type == "object")' <<<"$jobs" >/dev/null 2>&1 || { echo '{"job":"?","phase":"?","pod":"?"}'; return; }
  name="$(jq -r '[.items[]] | sort_by(.metadata.creationTimestamp) | last | .metadata.name // empty' <<<"$jobs")"
  [[ -n "$name" ]] || { echo '{"job":"-","phase":"-","pod":"-"}'; return; }
  pod="$(kc -n "${FLEET_NAMESPACE:-specclaw-fleet}" --request-timeout=10s get pods -l "job-name=$name" --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].status.phase}' 2>/dev/null)" || pod="?"
  jq -c --arg n "$name" --arg p "${pod:--}" --argjson jobs "$jobs" '[.items[] | select(.metadata.name == $n)][0].status as $s
    | {job: $n, pod: $p, created: ([$jobs.items[]? | select(.metadata.name == $n)][0].metadata.creationTimestamp // ""), phase: (if ($s.succeeded // 0) > 0 then "complete" elif ($s.failed // 0) > 0 then "failed" elif ($s.active // 0) > 0 then "active" else "pending" end)}' <<<"$jobs"
}

status_row() {
  local c="$1" id wi recs
  id="$(work_item_id "$c")"
  [[ -n "$id" ]] || { jq -nc --arg c "$c" '{change: $c, work_item: null, note: "no work item", terminal: true}'; return; }
  local consent=unknown rc=0 wi_ok=1 recs_ok=1
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$c" 2>/dev/null)" && jq -e 'type == "object"' <<<"$wi" >/dev/null 2>&1 || { wi='{}'; wi_ok=0; }
  recs="$(azdo_issue records "$SPECCLAW_DIR" "$c" 2>/dev/null)" && jq -e 'type == "object"' <<<"$recs" >/dev/null 2>&1 || { recs='{}'; recs_ok=0; }
  if (( wi_ok )); then F_CHANGE="$c"; gate_owner "$wi" || rc=$?
    case "$rc" in 0) consent=assignee ;; 10) consent=none ;; 11|12) consent=other ;; esac; fi
  jq -nc --arg c "$c" --arg id "$id" --arg since "$S_SINCE" --arg consent "$consent" --argjson wiok "$wi_ok" --argjson recok "$recs_ok" --argjson wi "$wi" --argjson r "$recs" --argjson job "$(status_job "$c")" --argjson runs "${S_RUNS:-[]}" '
    ($wi.fields["System.Tags"] // "" | ascii_downcase | split(";") | map(gsub("^\\s+|\\s+$"; ""))) as $t
    | ([$runs[] | select(.change == $c)] | last) as $run
    | (if ($run.queued // "") != "" then $run.queued else $since end) as $base
    | ([$r.records[]? | select((.at | sub("\\.[0-9]+"; "")) >= $base)] | first) as $rec
    | {change: $c, work_item: $id, state: (if $wiok == 0 then "?" else $wi.fields["System.State"] end),
       assignee: (if $wiok == 0 then "?" else ($wi.fields["System.AssignedTo"].uniqueName // "-") end),
       tags: [("auto", "dispatched", "refused") | select(("fleet:" + .) as $x | $t | index($x))],
       record: (if $recok == 0 then {state: "?"} elif $rec then $rec
         elif $consent == "unknown" then {state: "?"} elif $consent == "none" then {state: "not-opted-in"} elif $consent == "other" then {state: "not-opted-in (fleet:auto not added by the assignee)"}
         else {state: "waiting"} end), cluster: $job}
    | if .record.state == "waiting" and $run and $run.status == "completed" and ($run.queued // "") != "" and .cluster.job != "?" and ((.cluster.created // "") < $base)
      then .record = {state: "did-not-run", exit: "pipeline \($run.id) \($run.result)"}
      elif .record.state == "waiting" and $run then .record.exit = "pipeline \($run.id) \($run.status)" else . end
    | .terminal = ((.record.state | IN("pr_open", "failed", "refused", "did-not-run")) or (.tags | index("refused")) or ($consent | IN("none", "other"))
        or (.cluster.phase == "failed" and (.cluster.created // "") >= $base))'
}
