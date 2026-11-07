# shellcheck shell=bash
trigger_gates() {
  local wi rc=0 n
  n="$(work_item_id "$T_CHANGE")"
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$T_CHANGE")" || die "$T_CHANGE: could not read the work item"
  gate_owner "$wi" || rc=$?
  case "$rc" in
    0) ;;
    11) die "$T_CHANGE: work item #$n has no assignee; assign the person whose plan will run it" ;;
    13) die "$T_CHANGE: could not read the work item history" ;;
    *) echo "ERROR: $T_CHANGE: ${G_ASSIGNEE:-the assignee} must add the fleet:auto tag to work item #$n themselves" >&2; exit 4 ;;
  esac
  [[ -n "${FLEET_VAULT:-}" ]] || die "No Key Vault: set FLEET_VAULT"
  rc=0
  fetch_credential "$FLEET_VAULT" "$(secret_name "$T_AGENT" "$(upn_hash "$G_ASSIGNEE")")" >/dev/null || rc=$?
  case "$rc" in
    0) ;;
    1) die "$T_CHANGE: $G_ASSIGNEE has no registered $T_AGENT credential; they run: specclaw-fleet login --agent $T_AGENT" ;;
    *) die "$T_CHANGE: could not read Key Vault $FLEET_VAULT" ;;
  esac
}
