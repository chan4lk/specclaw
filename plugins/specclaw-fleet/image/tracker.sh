# shellcheck shell=bash
tracker_dir() {
  local dir="$WORK/fallback/.specclaw"
  if [[ -d "$REPO/.specclaw/changes/$FLEET_CHANGE" ]]; then printf '%s' "$REPO/.specclaw"; return 0; fi
  mkdir -p "$dir/changes/$FLEET_CHANGE"
  printf '**Azure Boards Work Item:** [#%s](fleet)\n' "${FLEET_WORK_ITEM:-0}" > "$dir/changes/$FLEET_CHANGE/status.md"
  printf '%s\n' "${FLEET_AZDO_CONFIG:-}" > "$dir/config.yaml"
  printf '%s' "$dir"
}

record() {
  specclaw-azdo-issue fields "$(tracker_dir)" "$FLEET_CHANGE" "$@" >/dev/null 2>&1 \
    || echo "WARNING: work item update failed: $*" >&2
}
