# shellcheck shell=bash disable=SC2034
codex_slot_state() {
  local json err="$FLEET_TMPDIR/get.err"
  if ! json="$(kc -n "$F_NS" --request-timeout=15s get job "$(codex_job_name)" -o json 2>"$err")"; then
    grep -q NotFound "$err" && { echo free; return 0; }
    echo "error $(head -n1 "$err")"; return 0
  fi
  local s
  s="$(jq -r 'if type != "object" then error("not a Job")
    elif ([.status.conditions[]? | select((.type == "Complete" or .type == "Failed") and .status == "True")] | length) > 0
      or ((.status.active // 0) == 0 and ((.status.succeeded // 0) > 0 or (.status.failed // 0) > 0))
    then "finished \(.metadata.uid // "")" else "active" end' <<<"$json" 2>/dev/null)" || s=""
  [[ "$s" == active || "$s" =~ ^finished\ [A-Za-z0-9-]+$ ]] || s="error unparsable Job JSON"
  echo "$s"
}

claim_codex_slot() {
  local state
  state="$(codex_slot_state)"
  case "$state" in
    active) busy "assignee already has an unfinished codex job" ;;
    finished*) delete_job_if_uid "${state#finished }" ;;
    free) ;;
    *) die "$F_CHANGE: could not read Job $(codex_job_name): ${state#error }" ;;
  esac
}

delete_job_if_uid() {
  jq -nc --arg u "$1" '{kind: "DeleteOptions", apiVersion: "v1", propagationPolicy: "Background", preconditions: {uid: $u}}' \
    > "$FLEET_TMPDIR/delete.json"
  local err="$FLEET_TMPDIR/delete.err"
  kc delete --raw "/apis/batch/v1/namespaces/$F_NS/jobs/$(codex_job_name)" -f "$FLEET_TMPDIR/delete.json" >/dev/null 2>"$err" && return 0
  grep -Eq 'Precondition failed|NotFound' "$err" && return 0
  die "$F_CHANGE: could not replace finished Job $(codex_job_name): $(head -n1 "$err")"
}

check_only_busy() {
  [[ "$F_AGENT" == codex ]] || return 0
  case "$(codex_slot_state)" in
    active) busy "assignee already has an unfinished codex job" ;;
    free|finished*) ;;
    *) T_BUSY_CHECK="not-run (cluster unreadable here)" ;;
  esac
}
