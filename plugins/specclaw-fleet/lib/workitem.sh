# shellcheck shell=bash
azdo_issue() {
  local bin
  bin="$(command -v specclaw-azdo-issue || echo "$FLEET_ROOT/../specclaw-sync/bin/specclaw-azdo-issue")"
  "$bin" "$@"
}

record_run() {
  local change="$1"
  shift
  azdo_issue fields "$SPECCLAW_DIR" "$change" "$@" >/dev/null || warn "could not update the work item for $change"
}

refuse() {
  record_run "$1" state=failed "exit=refused: $2"
  die "$1: $2"
}

work_item_id() {
  grep -oE '^\*\*Azure Boards Work Item:\*\* \[#[0-9]+\]' "$SPECCLAW_DIR/changes/$1/status.md" 2>/dev/null \
    | grep -oE '[0-9]+' | head -1
}

proposal_approved() {
  [[ "$(jq -r '.phases.proposal.status // empty' "$SPECCLAW_DIR/changes/$1/state.json" 2>/dev/null)" == approved ]]
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

consented() {
  local assignee="$1" requester="${BUILD_REQUESTEDFOREMAIL:-}" tag
  local -a tags=()
  IFS=';' read -ra tags <<<"$2"
  for tag in "${tags[@]}"; do
    tag="${tag#"${tag%%[![:space:]]*}"}"
    [[ "${tag%"${tag##*[![:space:]]}"}" == fleet:auto ]] && return 0
  done
  [[ -n "$requester" && "$(lower "$requester")" == "$(lower "$assignee")" ]]
}

fetch_credential() {
  local value err="$FLEET_TMPDIR/fetch.err"
  if ! value="$(az keyvault secret show --vault-name "$1" --name "$2" --query value -o tsv 2>"$err")"; then
    secret_not_found "$err" && return 1
    return 2
  fi
  [[ -n "$value" && "$value" != __unset__ ]] || return 1
  printf '%s' "$value"
}

