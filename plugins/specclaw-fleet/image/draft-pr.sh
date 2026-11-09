# shellcheck shell=bash
azdo_api() {
  local hdr="$HOME/.fleet/azdo-auth"
  [[ -s "$hdr" ]] || (umask 077 && mkdir -p "$HOME/.fleet" \
    && printf 'Authorization: Basic %s\n' "$(printf ':%s' "$AZDO_TOKEN" | base64 | tr -d '\n')" > "$hdr")
  curl -sf -m 30 -H @"$hdr" -H 'Content-Type: application/json' "$@"
}

pr_description() {
  local dir; dir="$REPO/.specclaw/$(item_kind)/$FLEET_CHANGE"
  { if [[ "${FLEET_PR_DRAFT:-true}" == true ]]; then echo "Opened as a **draft** by specclaw-fleet: verify did not pass, so a human decides what happens next."
    else echo "Opened by specclaw-fleet: integration of feature $FLEET_CHANGE passed its checks."; fi
    echo; echo "Work item: #${FLEET_WORK_ITEM:-?}"; echo
    sed -n '/^## Verify/,$p' "$dir/change.md" "$dir/verify-report.md" 2>/dev/null | head -c 2000
    echo; echo "### Open follow-ups"; head -c 1200 "$dir/follow-ups.md" 2>/dev/null; } | head -c 3800
}

ensure_pr() {
  local branch="$1" url api id
  url="$(jq -r '.phases.pr.url // empty' "$STATE" 2>/dev/null)"
  [[ -n "$url" ]] && { echo "$url false"; return 0; }
  [[ -n "$branch" ]] || return 0
  api="https://dev.azure.com/$AZDO_ORG/$AZDO_PROJECT/_apis/git/repositories/${FLEET_REPO_URL##*/}/pullrequests"
  local found isdraft
  found="$(azdo_api "$api?searchCriteria.sourceRefName=refs/heads/$branch&searchCriteria.status=active&api-version=7.1")" || return 0
  id="$(jq -r '.value[0].pullRequestId // empty' <<<"$found")"; isdraft="$(jq -r '.value[0].isDraft // false' <<<"$found")"
  if [[ -n "$id" && "$isdraft" == true && "${FLEET_PR_DRAFT:-true}" == false ]]; then
    azdo_api -X PATCH "$api/$id?api-version=7.1" --data-binary '{"isDraft": false}' >/dev/null && isdraft=false
  fi
  [[ -n "$id" ]] && { echo "${FLEET_REPO_URL}/pullrequest/$id $isdraft"; return 0; }
  [[ -n "$id" ]] || id="$(jq -n --arg s "refs/heads/$branch" --arg t "refs/heads/$SPECCLAW_PR_TARGET" --arg c "$FLEET_CHANGE" \
      --arg d "$(pr_description)" --arg w "${FLEET_WORK_ITEM:-}" --arg dr "${FLEET_PR_DRAFT:-true}" \
      '{sourceRefName: $s, targetRefName: $t, description: $d, isDraft: ($dr == "true"),
        title: (if $dr == "true" then "[draft] " + $c + ": verify did not pass" else $c + ": integration verified" end),
        workItemRefs: (if $w == "" then [] else [{id: $w}] end)}' \
    | azdo_api -X POST "$api?api-version=7.1" --data-binary @- | jq -r '.pullRequestId // empty')" || return 0
  [[ -n "$id" ]] && echo "${FLEET_REPO_URL}/pullrequest/$id ${FLEET_PR_DRAFT:-true}"
}

deliver() {
  trap '' TERM
  local branch pr draft
  branch="$(push_change_branch)"
  read -r pr draft < <(ensure_pr "$branch")
  show_agent_log
  record "state=$([[ -n "$pr" ]] && echo pr_open || echo failed)" "exit=$1" "branch=$branch" "pr=${pr:-none}" "draft=${draft:-false}"
  finish "$2"
}
