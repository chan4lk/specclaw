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

has_auto_tag() {
  local tag
  local -a tags=()
  IFS=';' read -ra tags <<<"$1"
  for tag in "${tags[@]}"; do
    tag="${tag#"${tag%%[![:space:]]*}"}"
    [[ "$(lower "${tag%"${tag##*[![:space:]]}"}")" == fleet:auto ]] && return 0
  done
  return 1
}

auto_tagged_by() {
  azdo_issue updates "$SPECCLAW_DIR" "$F_CHANGE" | jq -r '
    def auto: ascii_downcase | split(";") | map(gsub("^\\s+|\\s+$"; "")) | index("fleet:auto") != null;
    [.value[] | .fields["System.Tags"]? as $t | select($t != null)
      | select(($t.newValue // "" | auto) and (($t.oldValue // "" | auto) | not))]
    | last | .revisedBy.uniqueName // empty'
}

consented() {
  local assignee="$1" requester="${BUILD_REQUESTEDFOREMAIL:-}" tagger
  if has_auto_tag "$2"; then
    tagger="$(auto_tagged_by)" || die "$F_CHANGE: could not read the work item history"
    [[ "$(lower "$tagger")" == "$(lower "$assignee")" ]] && return 0
  fi
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

