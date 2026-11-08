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

claim_codex_slot() {
  local json state err="$FLEET_TMPDIR/get.err"
  if ! json="$(kubectl -n "$F_NS" get job "$F_JOB" -o json 2>"$err")"; then
    grep -q NotFound "$err" && return 0
    die "$F_CHANGE: could not read Job $F_JOB: $(head -n1 "$err")"
  fi
  state="$(jq -r '
    if ([.status.conditions[]? | select((.type == "Complete" or .type == "Failed") and .status == "True")] | length) > 0
      or ((.status.active // 0) == 0 and ((.status.succeeded // 0) > 0 or (.status.failed // 0) > 0))
    then "finished \(.metadata.uid)" else "active" end' <<<"$json")"
  case "$state" in
    active) busy "assignee already has an unfinished codex job" ;;
    finished*) delete_job_if_uid "${state#finished }" ;;
  esac
}

delete_job_if_uid() {
  jq -nc --arg u "$1" '{kind: "DeleteOptions", apiVersion: "v1", propagationPolicy: "Background", preconditions: {uid: $u}}' \
    > "$FLEET_TMPDIR/delete.json"
  local err="$FLEET_TMPDIR/delete.err"
  kubectl delete --raw "/apis/batch/v1/namespaces/$F_NS/jobs/$F_JOB" -f "$FLEET_TMPDIR/delete.json" >/dev/null 2>"$err" && return 0
  grep -Eq 'Precondition failed|NotFound' "$err" && return 0
  die "$F_CHANGE: could not replace finished Job $F_JOB: $(head -n1 "$err")"
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
    "requested_by=${BUILD_REQUESTEDFOR:-${USER:-unknown}}" "dispatched_commit=$F_COMMIT" state=dispatched
  jq -nc --arg j "$F_JOB" --arg a "$F_AGENT" --arg w "$F_WI" '{ok: true, job: $j, agent: $a, work_item: $w}'
}
