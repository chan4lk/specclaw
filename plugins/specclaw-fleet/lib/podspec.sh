# shellcheck shell=bash disable=SC2034
parse_pod_inputs() {
  F_CLAUDE_VERSION="${FLEET_CLAUDE_VERSION:-}"
  if [[ "$F_AGENT" == claude || -n "$F_CLAUDE_VERSION" ]]; then
    [[ "$F_CLAUDE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "FLEET_CLAUDE_VERSION must be a release like 2.1.319 (required for claude jobs)"
  fi
  F_PULL_SECRET="${FLEET_IMAGE_PULL_SECRET:-}"
  [[ -z "$F_PULL_SECRET" || "$F_PULL_SECRET" =~ ^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$ ]] \
    || die "FLEET_IMAGE_PULL_SECRET is not a valid secret name"
  F_MODE="${FLEET_MODE:-}" F_MERGE_REF="${FLEET_MERGE_REF:-}" F_PR_TARGET="${FLEET_PR_TARGET:-}"
  [[ -z "$F_MODE" || "$F_MODE" == integrate ]] || die "FLEET_MODE must be empty or integrate"
  local r; for r in "$F_MERGE_REF" "$F_PR_TARGET"; do
    [[ -z "$r" || ( "$r" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$r" != *..* ) ]] || die "'$r' is not a valid branch name"
  done
  F_NODE_KEY="" F_NODE_VALUE=""
  if [[ -n "${FLEET_NODE_LABEL:-}" ]]; then
    [[ "$FLEET_NODE_LABEL" =~ ^([a-z0-9.-]+/)?[A-Za-z0-9][-A-Za-z0-9_.]{0,62}=[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$ ]] \
      || die "FLEET_NODE_LABEL must be key=value"
    F_NODE_KEY="${FLEET_NODE_LABEL%%=*}" F_NODE_VALUE="${FLEET_NODE_LABEL#*=}"
  fi
}

render_pod_extras() {
  [[ -n "$F_PULL_SECRET" ]] && printf '      imagePullSecrets: [{name: %s}]\n' "$F_PULL_SECRET"
  if [[ -n "$F_NODE_KEY" ]]; then
    printf '      nodeSelector: {"%s": "%s"}\n' "$F_NODE_KEY" "$F_NODE_VALUE"
    printf '      tolerations: [{key: "%s", operator: Equal, value: "%s", effect: NoSchedule}]\n' "$F_NODE_KEY" "$F_NODE_VALUE"
  fi
  return 0
}

render_run_env() {
  [[ -n "$F_MODE" ]] && printf '            - {name: FLEET_MODE, value: %s}\n' "$(yaml_str "$F_MODE")"
  [[ -n "$F_MERGE_REF" ]] && printf '            - {name: FLEET_MERGE_REF, value: %s}\n' "$(yaml_str "$F_MERGE_REF")"
  [[ -n "$F_PR_TARGET" ]] && printf '            - {name: FLEET_PR_TARGET, value: %s}\n' "$(yaml_str "$F_PR_TARGET")"
  return 0
}
