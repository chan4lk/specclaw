# shellcheck shell=bash
create_manifests() {
  render_job | kubectl -n "$F_NS" create -f - >/dev/null || die "$F_CHANGE: could not create Job $F_JOB"
  local uid
  uid="$(kubectl -n "$F_NS" get job "$F_JOB" -o jsonpath='{.metadata.uid}')"
  printf '%s' "$F_CREDENTIAL" | base64 | tr -d '\n' > "$FLEET_B64"
  if [[ -z "$uid" ]] || ! render_secret "$(cat "$FLEET_B64")" "$uid" | kubectl -n "$F_NS" create -f - >/dev/null; then
    kubectl -n "$F_NS" delete job "$F_JOB" >/dev/null 2>&1 || true
    die "$F_CHANGE: could not create Secret $F_JOB (Job removed)"
  fi
}

launch_job() {
  FLEET_B64="$(umask 077 && mktemp)"
  trap 'rm -f "$FLEET_B64"' EXIT
  create_manifests
  local attempt cluster wi
  attempt="$(kubectl -n "$F_NS" get jobs -l "specclaw.fleet/change=$F_LABEL" -o name | wc -l | tr -d ' ')"
  cluster="$(kubectl config current-context 2>/dev/null || echo unknown)"
  wi="$(work_item_id "$F_CHANGE")"
  record_run "$F_CHANGE" "agent=$F_AGENT" "job=$F_JOB" "cluster=$cluster" \
    "branch=$(cfg_val git.branch_prefix specclaw/)$F_CHANGE" "attempt=$attempt" \
    "requested_by=${BUILD_REQUESTEDFOR:-${USER:-unknown}}" state=dispatched
  jq -nc --arg j "$F_JOB" --arg a "$F_AGENT" --arg w "$wi" '{ok: true, job: $j, agent: $a, work_item: $w}'
}
