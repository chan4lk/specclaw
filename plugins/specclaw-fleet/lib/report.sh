# shellcheck shell=bash disable=SC2034
parse_report_args() {
  R_JSON=0 R_HTML="" R_SAVE=0 R_SINCE="" R_FEATURE="" R_CHANGES=()
  while (($#)); do
    case "$1" in
      --json) R_JSON=1 ;;
      --save) R_SAVE=1 ;;
      --html) need_value "$1" "${2:-}"; R_HTML="$2"; shift ;;
      --since) need_value "$1" "${2:-}"; R_SINCE="$2"; shift ;;
      --feature) need_value "$1" "${2:-}"; R_FEATURE="$2"; shift ;;
      -*) die "Unknown flag: $1" ;;
      *) R_CHANGES+=("$1") ;;
    esac
    shift
  done
  [[ -z "$R_SINCE" || "$R_SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "--since must be UTC like 2026-11-08T03:00:00Z"
  [[ -n "$R_FEATURE" && ${#R_CHANGES[@]} -gt 0 ]] && die "report takes changes or --feature, not both"
  return 0
}

report_scope() {
  local d c
  if [[ -n "$R_FEATURE" ]]; then feature_waves "$R_FEATURE"; return; fi
  if (( ${#R_CHANGES[@]} )); then printf '%s\t\n' "${R_CHANGES[@]}"; return; fi
  for d in "$SPECCLAW_DIR"/changes/*/; do c="$(basename "$d")"; proposal_approved "$c" && printf '%s\t\n' "$c"; done
  return 0
}

REPORT_RUN='[.records[]? | objects] as $r | ($r | map(.state) | index("dispatched")) as $i
  | if ($r | length) == 0 then null else ($r[0:(($i // (($r | length) - 1)) + 1)] | reverse) as $run
    | ($run | add) + {dispatched_at: $run[0].at, state: $run[-1].state,
        running_at: ([$run[] | select(.state == "running") | .at] | last),
        ended_at: ([$run[] | select(.state | IN("pr_open", "failed")) | .at] | last)}
    | if $since != "" and ((.dispatched_at // "") | sub("\\.[0-9]+"; "")) < $since then null else . end end'

REPORT_ROW='def t: if . == null or . == "" or (tostring | startswith("0001")) then null else sub("\\.[0-9]+"; "") end;
  def n: if . == null or . == "" then null else (tonumber? // null) end;
  def secs(a; b): if a and b then (b | fromdateiso8601) - (a | fromdateiso8601) else null end;
  ($r.agent_started // $r.running_at | t) as $s0 | ($r.agent_ended // $r.ended_at | t) as $s1
  | {change: $c, work_item: (if $id == "" then null else $id end), wave: ($w | n), state: $r.state, exit: $r.exit,
     pipeline_run: $r.pipeline_run, dispatched: ($r.dispatched_at | t),
     queued: ($b.queueTime | t), started: ($b.startTime | t), finished: ($b.finishTime | t),
     job: ($j.job // $r.job), phase: $j.phase, agent_started: $s0, agent_ended: $s1,
     agent_s: (($r.agent_s | n) // secs($s0; $s1)), claude_fetch_s: ($r.claude_fetch_s | n),
     review_rounds: ($r.review_rounds | n), agent_commits: ($r.agent_commits | n),
     cost_usd: ($r.cost_usd | n), turns: ($r.turns | n), model: $r.model,
     pr: (if ($r.pr // "none") == "none" then null else $r.pr end),
     pr_status: $p.status, pr_opened: ($p.creationDate | t), pr_closed: ($p.closedDate | t)}'

api_obj() {
  local out
  out="$(azdo_rest "$1" 2>/dev/null)" || { echo '{}'; return 0; }
  jq -c 'if type == "object" then . else {} end' <<<"$out" 2>/dev/null || echo '{}'
}

report_row() {
  local c="$1" w="$2" id recs run pr p='{}' b='{}' j='{}' bid
  id="$(work_item_id "$c")" || id=""
  recs="$(azdo_issue records "$SPECCLAW_DIR" "$c" 2>/dev/null)" || recs='{}'
  run="$(jq -c --arg since "$R_SINCE" "$REPORT_RUN" <<<"$recs" 2>/dev/null)" || run=null
  if [[ -z "$run" || "$run" == null ]]; then
    (( ${#R_CHANGES[@]} )) && jq -nc --arg c "$c" --arg id "$id" '{change: $c, work_item: (if $id == "" then null else $id end), state: null}'
    return 0
  fi
  pr="$(jq -r '(.pr // "") | capture("/pullrequest/(?<n>[0-9]+)$").n // empty' <<<"$run")"
  [[ -z "$pr" ]] || p="$(api_obj "git/pullrequests/$pr?api-version=7.1")"
  bid="$(jq -r '.pipeline_run // "" | select(test("^[0-9]+$"))' <<<"$run")"
  [[ -z "$bid" ]] || b="$(api_obj "build/builds/$bid?api-version=7.1")"
  jq -e '.state | IN("dispatched", "running")' <<<"$run" >/dev/null && j="$(status_job "$c")"
  jq -nc --arg c "$c" --arg id "$id" --arg w "$w" --argjson r "$run" --argjson p "$p" --argjson b "$b" --argjson j "$j" "$REPORT_ROW"
}

fleet_report() {
  parse_report_args "$@"
  load_azdo_env
  local rows c w scope
  scope="$(report_scope)" || exit 1
  rows="$(while IFS=$'\t' read -r w c; do [[ -n "$c" ]] || { c="$w"; w=""; }; [[ -n "$c" ]] && report_row "$c" "$w"; done <<<"$scope" | jq -sc '.')"
  report_emit "$rows"
}
