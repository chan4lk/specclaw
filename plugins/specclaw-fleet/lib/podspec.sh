# shellcheck shell=bash disable=SC2034
parse_pod_inputs() {
  F_CLAUDE_VERSION="${FLEET_CLAUDE_VERSION:-}"
  if [[ "$F_AGENT" == claude ]]; then
    [[ "$F_CLAUDE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "FLEET_CLAUDE_VERSION must be set to a release like 2.1.319 for claude jobs"
  fi
  F_PULL_SECRET="${FLEET_IMAGE_PULL_SECRET:-}"
  [[ -z "$F_PULL_SECRET" || "$F_PULL_SECRET" =~ ^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$ ]] \
    || die "FLEET_IMAGE_PULL_SECRET is not a valid secret name"
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
