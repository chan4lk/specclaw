# shellcheck shell=bash
render_secret() {
  cat <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: $F_SECRET_OBJ
  namespace: $F_NS
  labels:
    app.kubernetes.io/part-of: specclaw-fleet
  ownerReferences:
    - {apiVersion: batch/v1, kind: Job, name: $F_JOB, uid: "$2"}
type: Opaque
data:
  credential: $1
YAML
}

create_job() {
  local err
  err="$(render_job | kubectl -n "$F_NS" create -f - 2>&1 >/dev/null)" && return 0
  [[ "$F_AGENT" == codex && "$err" == *AlreadyExists* ]] && busy "assignee already has an unfinished codex job"
  die "$F_CHANGE: could not create Job $F_JOB: $err"
}

create_manifests() {
  if [[ "$F_AGENT" == codex ]]; then claim_codex_slot; fi
  create_job
  local uid
  uid="$(kubectl -n "$F_NS" get job "$F_JOB" -o jsonpath='{.metadata.uid}' 2>/dev/null)" || uid=""
  if [[ -z "$uid" ]] || ! render_secret "$(printf '%s' "$F_CREDENTIAL" | base64 | tr -d '\n')" "$uid" \
      | kubectl -n "$F_NS" create -f - >/dev/null; then
    kubectl -n "$F_NS" delete job "$F_JOB" >/dev/null 2>&1 || true
    die "$F_CHANGE: could not create Secret $F_SECRET_OBJ (Job removed)"
  fi
}

launch_job() {
  claim_change
  local rc=0
  ( create_manifests ) || rc=$?
  if (( rc )); then
    azdo_issue untag "$SPECCLAW_DIR" "$F_CHANGE" fleet:dispatched >/dev/null || warn "could not release the fleet:dispatched claim"
    exit "$rc"
  fi
  local attempt cluster
  attempt="$(kubectl -n "$F_NS" get jobs -l "specclaw.fleet/change=$F_LABEL" -o name | wc -l | tr -d ' ')" || attempt=unknown
  cluster="$(kubectl config current-context 2>/dev/null || echo unknown)"
  record_run "$F_CHANGE" "agent=$F_AGENT" "job=$F_JOB" "cluster=$cluster" "attempt=$attempt" \
    "requested_by=${BUILD_REQUESTEDFOR:-${USER:-unknown}}" "dispatched_commit=$F_COMMIT" "image=$F_IMAGE" "claude_version=${F_CLAUDE_VERSION:-none}" state=dispatched
  jq -nc --arg j "$F_JOB" --arg a "$F_AGENT" --arg w "$F_WI" '{ok: true, job: $j, agent: $a, work_item: $w}'
}
