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

fleet_feature() {
  local sub="${1:-}"; shift || true
  [[ -n "${1:-}" ]] || die "Usage: specclaw-fleet feature plan <module> [--json]"
  case "$sub" in
    plan) feature_plan "$@" ;;
    *) die "Usage: specclaw-fleet feature plan <module> [--json]" ;;
  esac
}
