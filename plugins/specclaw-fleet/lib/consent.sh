# shellcheck shell=bash
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
  local assignee="$1" tagger
  tagger="$(auto_tagged_by)" || refuse "$F_CHANGE" "could not read the work item history to confirm who added fleet:auto"
  [[ -n "$tagger" && "$(lower "$tagger")" == "$(lower "$assignee")" ]]
}
