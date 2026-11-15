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

redact() { sed -E 's/sk-ant-[A-Za-z0-9_-]+/sk-ant-<redacted>/g; s/eyJ[A-Za-z0-9._-]{20,}/<jwt-redacted>/g; s/[A-Za-z0-9+\/_-]{40,}/<redacted>/g'; }

show_agent_log() {
  [[ -f "$STATUS/agent.log" ]] || return 0
  echo "---- agent log (last 4000 bytes, secrets redacted) ----" >&2
  tail -c 4000 "$STATUS/agent.log" | redact >&2
}

# Retries the push (FLEET_PUSH_ATTEMPTS, pauses FLEET_PUSH_PAUSES, last repeats); repacks before the final try.
push_change_branch() {
  local branch err i n="${FLEET_PUSH_ATTEMPTS:-4}" p
  local -a pauses
  branch="$(change_branch)"
  [[ -n "$branch" && "$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "$branch" ]] || return 0
  [[ "$n" =~ ^[1-9]$ ]] || { echo "WARNING: FLEET_PUSH_ATTEMPTS=$n is not 1-9; using 4" >&2; n=4; }
  read -ra pauses <<<"${FLEET_PUSH_PAUSES:-5 15 45}"
  for ((i = 1; i <= n; i++)); do
    (( i == n && n > 1 )) && git -C "$REPO" repack -a -d -f -q >&2
    err="$(git -C "$REPO" push -q -u origin HEAD 2>&1 >/dev/null)" \
      && { rm -f "$STATUS/push-error" "${FLEET_BUNDLE_DIR:-/fleet/bundles}"/work.{bundle,base}; printf '%s' "$branch"; return 0; }
    printf '%s\n' "$err" | grep -v '^[[:space:]]*$' | tail -n 1 | redact > "$STATUS/push-error"
    echo "WARNING: push $i/$n of $branch failed: $(cat "$STATUS/push-error")" >&2
    p="${pauses[i - 1]:-${pauses[${#pauses[@]} - 1]:-0}}"
    (( i < n )) && sleep "$p"
  done
  return 1
}

# After a fully failed push, keeps BUNDLE_BASE..<change branch> in the per-change bundle folder (FR-7); prints saved or none.
save_bundle() {
  local b d="${FLEET_BUNDLE_DIR:-/fleet/bundles}"
  b="$(change_branch)"
  [[ -n "${BUNDLE_BASE:-}" && -n "$b" && -d "$d" && -w "$d" ]] \
    && git -C "$REPO" bundle create "$d/work.bundle.tmp" "$BUNDLE_BASE..refs/heads/$b" >/dev/null 2>&1 \
    && mv -f "$d/work.bundle.tmp" "$d/work.bundle" && printf '%s\n' "$BUNDLE_BASE" > "$d/work.base" && { echo saved; return 0; }
  rm -f "$d/work.bundle.tmp" 2>/dev/null; echo none
}
