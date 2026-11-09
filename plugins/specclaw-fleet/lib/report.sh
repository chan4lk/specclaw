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

first_obj() {
  local out
  out="$(jq -cn 'first(inputs | objects)' <<<"${1:-}" 2>/dev/null | head -n1)"
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; else echo '{"_unread":true}'; fi
}

api_obj() {
  local out
  out="$(azdo_rest "$1" 2>/dev/null)" || { echo '{"_unread":true}'; return 0; }
  first_obj "$out"
}

report_row() {
  local c="$1" w="$2" id recs run pr p='{}' b='{}' j='{}' bid
  id="$(work_item_id "$c")" || id=""
  recs="$(azdo_issue records "$SPECCLAW_DIR" "$c" 2>/dev/null)" && jq -e '.records | type == "array"' <<<"$recs" >/dev/null 2>&1 \
    || { unknown_row "$c" "$id" "records unreadable"; return 0; }
  run="$(jq -c --arg since "$R_SINCE" "$REPORT_RUN" <<<"$recs" 2>/dev/null)" || { unknown_row "$c" "$id" "records unparsable"; return 0; }
  if [[ -z "$run" || "$run" == null ]]; then
    (( ${#R_CHANGES[@]} )) && jq -nc --arg c "$c" --arg id "$id" '{change: $c, work_item: (if $id == "" then null else $id end), state: null}'
    return 0
  fi
  pr="$(jq -r '(.pr // "") | capture("/pullrequest/(?<n>[0-9]+)$").n // empty' <<<"$run")"
  [[ -z "$pr" ]] || p="$(api_obj "git/pullrequests/$pr?api-version=7.1")"
  bid="$(jq -r '.pipeline_run // "" | select(test("^[0-9]+$"))' <<<"$run")"
  [[ -z "$bid" ]] || b="$(api_obj "build/builds/$bid?api-version=7.1")"
  jq -e '.state | IN("dispatched", "running")' <<<"$run" >/dev/null && j="$(first_obj "$(status_job "$c")")"
  jq -nc --arg c "$c" --arg id "$id" --arg w "$w" --argjson r "$run" --argjson p "$p" --argjson b "$b" --argjson j "$j" "$REPORT_ROW" \
    || unknown_row "$c" "$id" "row could not be built"
}

unknown_row() {
  warn "$1: $3; shown as ?"
  jq -nc --arg c "$1" --arg id "$2" --arg n "$3" '{change: $c, work_item: (if $id == "" then null else $id end), state: "?", note: $n}'
}

fleet_report() {
  parse_report_args "$@"
  load_azdo_env
  local rows c w scope
  scope="$(report_scope)" || exit 1
  rows="$(while IFS=$'\t' read -r w c; do [[ -n "$c" ]] || { c="$w"; w=""; }; [[ -n "$c" ]] && report_row "$c" "$w"; done <<<"$scope" | jq -sc '.')"
  report_emit "$rows"
}
