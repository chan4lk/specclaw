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

show_agent_log() {
  [[ -f "$STATUS/agent.log" ]] || return 0
  echo "---- agent log (last 4000 bytes, secrets redacted) ----" >&2
  tail -c 4000 "$STATUS/agent.log" \
    | sed -E 's/sk-ant-[A-Za-z0-9_-]+/sk-ant-<redacted>/g; s/eyJ[A-Za-z0-9._-]{20,}/<jwt-redacted>/g; s/[A-Za-z0-9+\/_-]{40,}/<redacted>/g' >&2
}

push_change_branch() {
  local branch
  branch="$(jq -r '.branch // empty' "$STATE" 2>/dev/null)"
  [[ -n "$branch" && "$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "$branch" ]] || return 0
  git -C "$REPO" push -q -u origin HEAD >&2 || { echo "WARNING: could not push $branch" >&2; return 0; }
  printf '%s' "$branch"
}
