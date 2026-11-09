# shellcheck shell=bash
feature_plan() {
  local module="$1" states
  load_azdo_env
  states="$(feature_states "$module")" || exit 1
  if [[ "${2:-}" == --json ]]; then jq -c --arg m "$module" '{feature: $m, members: .}' <<<"$states"; return 0; fi
  echo "feature $module"
  jq -r '.[] | "  wave \(.wave)  \(.change)\t\(.state)\t\(if (.depends_on | length) > 0 then "depends on " + (.depends_on | join(",")) else "" end)"' <<<"$states" \
    | awk -F'\t' '{ printf "%-46s %-14s %s\n", $1, $2, $3 }'
}

feature_init() {
  local m="$1" d="$SPECCLAW_DIR/features/$1" waves
  waves="$(feature_waves "$m")" || exit 1
  load_azdo_env
  if [[ ! -f "$d/state.json" ]]; then
    mkdir -p "$d"
    { printf '# Feature: %s\n\nCoordinated by specclaw-fleet. Members, by wave:\n\n' "$m"
      while IFS=$'\t' read -r w c; do printf -- '- wave %s: %s\n' "$w" "$c"; done <<<"$waves"; } > "$d/proposal.md"
    printf '# Status: feature %s\n\n' "$m" > "$d/status.md"
    jq -n --arg m "$m" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{change: $m, kind: "feature", phase: "proposal", phases: {proposal: {status: "approved", at: $at}}}' > "$d/state.json"
  fi
  [[ -n "$(work_item_id "$m")" ]] || azdo_issue create "$SPECCLAW_DIR" "$m" >&2 || die "could not create the feature work item"
  echo "feature $m: record in $d, work item #$(work_item_id "$m"). Next: specclaw-fleet optin $m <members>, commit and push $d, then specclaw-fleet feature start $m" >&2
}

fleet_feature() {
  local sub="${1:-}"; shift || true
  local usage="Usage: specclaw-fleet feature plan|init|start|advance <module> [--json]"
  [[ -n "${1:-}" ]] || die "$usage"
  case "$sub" in
    plan) feature_plan "$@" ;;
    init) feature_init "$1" ;;
    start) feature_start "$1" ;;
    advance) feature_advance "$1" ;;
    *) die "$usage" ;;
  esac
}
