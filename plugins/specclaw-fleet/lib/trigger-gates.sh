# shellcheck shell=bash
trigger_gates() {
  local wi assignee tags tagger rc=0
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$T_CHANGE")" || die "$T_CHANGE: could not read the work item"
  assignee="$(jq -r '.fields["System.AssignedTo"].uniqueName // empty' <<<"$wi")"
  tags="$(jq -r '.fields["System.Tags"] // empty' <<<"$wi")"
  [[ -n "$assignee" ]] || die "$T_CHANGE: work item #$(work_item_id "$T_CHANGE") has no assignee; assign the person whose plan will run it"
  has_auto_tag "$tags" || consent_missing "$assignee"
  tagger="$(auto_tagged_by)" || die "$T_CHANGE: could not read the work item history"
  [[ "$(lower "$tagger")" == "$(lower "$assignee")" ]] || consent_missing "$assignee"
  [[ -n "${FLEET_VAULT:-}" ]] || die "No Key Vault: set FLEET_VAULT"
  fetch_credential "$FLEET_VAULT" "$(secret_name "$T_AGENT" "$(upn_hash "$assignee")")" >/dev/null || rc=$?
  case "$rc" in
    0) ;;
    1) die "$T_CHANGE: $assignee has no registered $T_AGENT credential; they run: specclaw-fleet login --agent $T_AGENT" ;;
    *) die "$T_CHANGE: could not read Key Vault $FLEET_VAULT" ;;
  esac
}

consent_missing() {
  echo "ERROR: $T_CHANGE: $1 must add the fleet:auto tag to work item #$(work_item_id "$T_CHANGE") themselves" >&2
  exit 4
}
