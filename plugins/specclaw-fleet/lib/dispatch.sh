# shellcheck shell=bash disable=SC2034
parse_dispatch_args() {
  F_CHANGE="" F_AGENT="" F_REF="" F_VAULT="" F_DRY_RUN=0
  while (($#)); do
    case "$1" in
      --agent) need_value "$1" "${2:-}"; F_AGENT="$2"; shift 2 ;;
      --ref) need_value "$1" "${2:-}"; F_REF="$2"; shift 2 ;;
      --vault) need_value "$1" "${2:-}"; F_VAULT="$2"; shift 2 ;;
      --dry-run) F_DRY_RUN=1; shift ;;
      -*) die "Unknown flag: $1" ;;
      *) F_CHANGE="$1"; shift ;;
    esac
  done
  [[ -n "$F_CHANGE" ]] || die "Usage: specclaw-fleet dispatch <change> [--agent claude|codex] [--ref <branch>] [--vault <name>] [--dry-run]"
  F_AGENT="${F_AGENT:-$(cfg_val fleet.default_agent claude)}"
  [[ "$F_AGENT" == claude || "$F_AGENT" == codex ]] || die "Unknown agent '$F_AGENT' (expected claude or codex)"
  F_REF="${F_REF:-$(cfg_val git.base_branch main)}"
  F_VAULT="${F_VAULT:-$(cfg_val fleet.vault "")}"
  [[ -n "$F_VAULT" ]] || die "No Key Vault: pass --vault or set fleet.vault in config.yaml"
  F_NS="$(cfg_val fleet.namespace specclaw-fleet)"
  F_IMAGE="$(cfg_val fleet.image specclaw-fleet:latest)"
  F_DEADLINE=$(( 10#$(cfg_val fleet.deadline_minutes 120) * 60 ))
}

check_gates() {
  proposal_approved "$F_CHANGE" || die "$F_CHANGE: proposal is not approved"
  [[ -n "$(work_item_id "$F_CHANGE")" ]] || die "$F_CHANGE: no Azure Boards work item (run specclaw-azdo-issue create)"
  local wi assignee tags
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$F_CHANGE")" || die "$F_CHANGE: could not read the work item"
  assignee="$(jq -r '.fields["System.AssignedTo"].uniqueName // empty' <<<"$wi")"
  tags="$(jq -r '.fields["System.Tags"] // empty' <<<"$wi")"
  [[ -n "$assignee" ]] || refuse "$F_CHANGE" "work item has no assignee"
  consented "$assignee" "$tags" \
    || refuse "$F_CHANGE" "assignee $assignee has not consented (add tag fleet:auto, or trigger the run yourself)"
  F_HASH="$(upn_hash "$assignee")"
  F_SECRET="$(secret_name "$F_AGENT" "$F_HASH")"
  F_CREDENTIAL="$(fetch_credential "$F_VAULT" "$F_SECRET")" \
    || refuse "$F_CHANGE" "assignee has no registered $F_AGENT credential (run specclaw-fleet login --agent $F_AGENT)"
  if [[ "$F_AGENT" == codex ]] && codex_busy "$F_NS" "$F_HASH"; then
    refuse "$F_CHANGE" "assignee already has an unfinished codex job"
  fi
}

fleet_dispatch() {
  parse_dispatch_args "$@"
  check_gates
  F_JOB="$(job_name "$F_CHANGE")"
  F_LABEL="$(label_value "$F_CHANGE")"
  F_REPO="$(git -C "$SPECCLAW_DIR/.." remote get-url origin | sed -E 's#://[^@/]+@#://#')"
  if (( F_DRY_RUN )); then
    render_secret REDACTED
    echo ---
    render_job
    return 0
  fi
  launch_job
}
