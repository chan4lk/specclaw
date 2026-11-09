# shellcheck shell=bash
feature_plan() {
  local module="$1" json=0 wave c deps
  [[ "${2:-}" == --json ]] && json=1
  local waves; waves="$(feature_waves "$module")" || exit 1
  if (( json )); then
    while IFS=$'\t' read -r wave c; do
      jq -nc --arg c "$c" --argjson w "$wave" --arg d "$(change_deps "$c" | paste -sd, -)" '{change: $c, wave: $w, depends_on: ($d | split(",") | map(select(. != "")))}'
    done <<<"$waves" | jq -sc --arg m "$module" '{feature: $m, members: .}'
    return 0
  fi
  echo "feature $module"
  while IFS=$'\t' read -r wave c; do
    deps="$(change_deps "$c" | paste -sd, -)"
    printf '  wave %s  %-36s %s\n' "$wave" "$c" "${deps:+depends on $deps}"
  done <<<"$waves"
}

fleet_feature() {
  local sub="${1:-}"; shift || true
  [[ -n "${1:-}" ]] || die "Usage: specclaw-fleet feature plan <module> [--json]"
  case "$sub" in
    plan) feature_plan "$@" ;;
    *) die "Usage: specclaw-fleet feature plan <module> [--json]" ;;
  esac
}
