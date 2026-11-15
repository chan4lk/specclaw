# shellcheck shell=bash
BUNDLE_DIR="${FLEET_BUNDLE_DIR:-/fleet/bundles}"
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
# Each try is cut off after FLEET_PUSH_TIMEOUT s; nothing starts that would end past DELIVER_BY (set by the entrypoint), so the record and bundle still fit.
push_change_branch() {
  local branch err i rc s n="${FLEET_PUSH_ATTEMPTS:-}" p="${FLEET_PUSH_PAUSES:-}" t="${FLEET_PUSH_TIMEOUT:-}" end="${DELIVER_BY:-$((SECONDS + 300))}"
  local -a pauses
  branch="$(change_branch)"
  [[ -n "$branch" && "$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "$branch" ]] || return 0
  [[ -z "$n" || "$n" =~ ^[1-9]$ ]] || echo "WARNING: FLEET_PUSH_ATTEMPTS is not 1-9; using the default" >&2
  [[ "$n" =~ ^[1-9]$ ]] || n=4
  [[ -z "$p" || "$p" =~ ^[[:blank:]]*[0-9]+([[:blank:]]+[0-9]+)*[[:blank:]]*$ ]] || { echo "WARNING: FLEET_PUSH_PAUSES is not seconds separated by spaces; using the default" >&2; p=""; }
  [[ -z "$t" || "$t" =~ ^[1-9][0-9]{0,3}$ ]] || echo "WARNING: FLEET_PUSH_TIMEOUT is not whole seconds from 1 to 9999; using the default" >&2
  [[ "$t" =~ ^[1-9][0-9]{0,3}$ ]] || t=120
  read -ra pauses <<<"${p:-5 15 45}"
  for ((i = 1; i <= n; i++)); do
    s=0; (( i > 1 )) && s="$(( 10#${pauses[i - 2]:-${pauses[${#pauses[@]} - 1]}} ))"
    (( end - SECONDS > s + 5 )) || { echo "WARNING: delivery budget spent; push $i/$n of $branch and later ones skipped" >&2
      [[ -s "$STATUS/push-error" ]] || echo "push skipped: delivery budget spent" > "$STATUS/push-error"; break; }
    sleep "$s"
    (( i == n && n > 1 && end - SECONDS > 2 * t )) && timeout "$(( end - SECONDS - t ))" git -C "$REPO" repack -a -d -f -q >&2
    s=$(( end - SECONDS < t ? end - SECONDS : t ))
    err="$(timeout "$s" git -C "$REPO" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 push -q -u origin HEAD 2>&1 >/dev/null)"; rc=$?
    (( rc == 0 )) && { rm -f "$STATUS/push-error"; drop_bundle; printf '%s' "$branch"; return 0; }
    (( rc == 124 )) && err+=$'\n'"push timed out after ${s}s"
    printf '%s\n' "$err" | grep -v '^[[:space:]]*$' | tail -n 1 | redact > "$STATUS/push-error"
    echo "WARNING: push $i/$n of $branch failed: $(cat "$STATUS/push-error")" >&2
  done
  return 1
}

# After a fully failed push, keeps BUNDLE_BASE..<change branch> in the per-change bundle folder (FR-7); prints saved or none.
# Base first, then bundle, each renamed into place. A failed save keeps an older pair only while it still verifies.
save_bundle() {
  local b d="$BUNDLE_DIR" kept=""
  b="$(change_branch)"
  if [[ -f "$d/work.bundle" && -n "$b" ]] && ! bundle_held "refs/heads/$b"; then
    kept="$(set_bundle_aside)" || { echo none; return 0; }
    kept=",kept=$kept"
  fi
  [[ -n "${BUNDLE_BASE:-}" && -n "$b" && -d "$d" && -w "$d" ]] && printf '%s\n' "$BUNDLE_BASE" > "$d/work.base.tmp" \
    && git -C "$REPO" bundle create "$d/work.bundle.tmp" "$BUNDLE_BASE..refs/heads/$b" >/dev/null 2>&1 \
    && mv -f "$d/work.base.tmp" "$d/work.base" && mv -f "$d/work.bundle.tmp" "$d/work.bundle" && { echo "saved$kept"; return 0; }
  rm -f "$d"/work.{bundle,base}.tmp 2>/dev/null
  [[ ! -f "$d/work.bundle" ]] || git -C "$REPO" bundle verify "$d/work.bundle" >/dev/null 2>&1 || rm -f "$d"/work.{bundle,base} 2>/dev/null
  echo "none$kept"
}

# True when <ref> holds every tip in the saved bundle, or the file is no bundle at all.
bundle_held() {
  local heads tip _
  heads="$(git -C "$REPO" bundle list-heads "$BUNDLE_DIR/work.bundle" 2>/dev/null)" || return 0
  while read -r tip _; do
    [[ -z "$tip" ]] || git -C "$REPO" merge-base --is-ancestor "$tip" "$1" 2>/dev/null || return 1
  done <<<"$heads"
}

# A saved bundle with commits the branch lacks is never overwritten: it moves to the first free kept-<n>.* for the operator, and the record says kept=<name>.
set_bundle_aside() {
  local k n=1
  while [[ -e "$BUNDLE_DIR/kept-$n.bundle" || -e "$BUNDLE_DIR/kept-$n.base" ]]; do n=$((n + 1)); done
  k="$BUNDLE_DIR/kept-$n"
  mv -n "$BUNDLE_DIR/work.bundle" "$k.bundle" 2>/dev/null && [[ ! -e "$BUNDLE_DIR/work.bundle" ]] || return 1
  mv -n "$BUNDLE_DIR/work.base" "$k.base" 2>/dev/null || rm -f "$BUNDLE_DIR/work.base"
  echo "WARNING: set aside $k.bundle: it holds commits this branch does not" >&2
  printf '%s' "${k##*/}"
}

# After a good push the pair goes only when HEAD holds every tip in the bundle, or it is no bundle at all; else it is kept.
drop_bundle() {
  [[ -f "$BUNDLE_DIR/work.bundle" ]] || return 0
  bundle_held HEAD || { echo "WARNING: kept $BUNDLE_DIR/work.bundle: it holds commits the pushed branch does not" >&2; return 0; }
  rm -f "$BUNDLE_DIR"/work.{bundle,base}
}
