# shellcheck shell=bash disable=SC2034
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
  azdo_issue updates "$SPECCLAW_DIR" "$F_CHANGE" | jq -er '
    def auto: ascii_downcase | split(";") | map(gsub("^\\s+|\\s+$"; "")) | index("fleet:auto") != null;
    if (.value | type) != "array" then error("no history") else . end
    | [.value[] | .fields["System.Tags"]? as $t | select($t != null)
      | select(($t.newValue // "" | auto) and (($t.oldValue // "" | auto) | not))]
    | last | .revisedBy.uniqueName // ""' 2>/dev/null
}

gate_owner() {
  local wi="$1" tags tagger
  G_ASSIGNEE="$(jq -r '.fields["System.AssignedTo"].uniqueName // empty' <<<"$wi")"
  tags="$(jq -r '.fields["System.Tags"] // empty' <<<"$wi")"
  has_auto_tag "$tags" || return 10
  [[ -n "$G_ASSIGNEE" ]] || return 11
  tagger="$(auto_tagged_by)" || return 13
  [[ -n "$tagger" && "$(lower "$tagger")" == "$(lower "$G_ASSIGNEE")" ]] || return 12
}
