# shellcheck shell=bash
feature_dispatch() {
  local rc=0
  ( "$@" ) >&2 || rc=$?
  case "$rc" in 0|3|4|5) ;; *) F_ERRORS=$((F_ERRORS + 1)) ;; esac
  return "$rc"
}

feature_advance() {
  local m="$1" states c s n wi rc
  load_azdo_env
  states="$(feature_states "$m")" || exit 1
  F_ERRORS=0
  while IFS=$'\t' read -r c s; do
    case "$s" in
      ready) FLEET_REF="feature/$m" feature_dispatch fleet_dispatch "$c" || true ;;
      '?') echo "$c: state unknown (AzDO unreadable); not advanced" >&2; F_ERRORS=$((F_ERRORS + 1)) ;;
      stalled) echo "$c: stalled (abandoned PR, PR to another branch, or dispatched with no outcome); fix it or retry with trigger --retry" >&2
        F_ERRORS=$((F_ERRORS + 1)) ;;
      conflict)
        wi="$(azdo_issue show "$SPECCLAW_DIR" "$c" 2>/dev/null)" && jq -e 'type == "object"' <<<"$wi" >/dev/null 2>&1 \
          || { echo "$c: could not read the work item; conflict retry skipped" >&2; F_ERRORS=$((F_ERRORS + 1)); continue; }
        if wi_has_tag "$wi" fleet:conflict-retried; then
          record_run "$c" state=failed exit=merge-conflict "pr_target=feature/$m"
          azdo_issue tag "$SPECCLAW_DIR" "$c" fleet:refused >/dev/null || F_ERRORS=$((F_ERRORS + 1))
        else
          rc=0; FLEET_REF="feature/$m" FLEET_MERGE_REF="feature/$m" feature_dispatch fleet_dispatch "$c" --force || rc=$?
          (( rc == 0 )) && { azdo_issue tag "$SPECCLAW_DIR" "$c" fleet:conflict-retried >/dev/null || F_ERRORS=$((F_ERRORS + 1)); }
        fi ;;
    esac
  done < <(jq -r '.[] | "\(.change)\t\(.state)"' <<<"$states")
  n="$(jq '[.[] | select(.state != "merged")] | length' <<<"$states")"
  if (( n == 0 )); then
    FLEET_REF="feature/$m" FLEET_MODE=integrate FLEET_PR_TARGET="${FLEET_TRUSTED_BRANCH:-main}" feature_dispatch fleet_dispatch "$m" || true
  fi
  jq -c --arg m "$m" --argjson e "$F_ERRORS" '{feature: $m, errors: $e, members: .}' <<<"$states"
  (( F_ERRORS == 0 ))
}

feature_start() {
  local m="$1" remote="${FLEET_REMOTE:-origin}" ref="${FLEET_REF:-main}" root="$SPECCLAW_DIR/.." sc run
  [[ "$m" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || die "feature module '$m' must match ^[a-z0-9][a-z0-9-]{0,40}$"
  sc="$(basename "$SPECCLAW_DIR")"
  load_azdo_env
  git -C "$root" fetch -q "$remote" "$ref" 2>/dev/null || die "could not fetch $remote/$ref"
  git -C "$root" cat-file -e "FETCH_HEAD:$sc/features/$m/state.json" 2>/dev/null || die "feature $m is not on $remote/$ref; commit and push $sc/features/$m first"
  local lrc=0; git -C "$root" ls-remote --exit-code --heads "$remote" "refs/heads/feature/$m" >/dev/null || lrc=$?
  (( lrc == 0 || lrc == 2 )) || die "could not ask $remote whether feature/$m exists (git ls-remote exit $lrc)"
  if (( lrc == 2 )); then
    git -C "$root" push -q "$remote" "FETCH_HEAD:refs/heads/feature/$m" || die "could not create feature/$m on $remote"
    echo "created feature/$m from $remote/$ref" >&2
  fi
  local -a a; mapfile -t a < <(azdo_args)
  run="$(az pipelines run --name "${FLEET_PIPELINE:-specclaw-fleet}" --branch "feature/$m" "${a[@]}" \
    --parameters "change= " "agent= " --query id -o tsv)" || die "could not queue ${FLEET_PIPELINE:-specclaw-fleet} on feature/$m"
  jq -nc --arg m "$m" --arg r "$run" '{ok: true, feature: $m, branch: ("feature/" + $m), run: $r}'
}
