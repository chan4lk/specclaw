# shellcheck shell=bash disable=SC2034
parse_dispatch_args() {
  F_CHANGE="" F_AGENT="" F_REF="" F_VAULT="" F_DRY_RUN=0 F_FORCE=0
  while (($#)); do
    case "$1" in
      --agent) need_value "$1" "${2:-}"; F_AGENT="$2"; shift 2 ;;
      --ref) need_value "$1" "${2:-}"; F_REF="$2"; shift 2 ;;
      --vault) need_value "$1" "${2:-}"; F_VAULT="$2"; shift 2 ;;
      --dry-run) F_DRY_RUN=1; shift ;;
      --force) F_FORCE=1; shift ;;
      -*) die "Unknown flag: $1" ;;
      *) F_CHANGE="$1"; shift ;;
    esac
  done
  [[ -n "$F_CHANGE" ]] || die "Usage: specclaw-fleet dispatch <change> [--agent claude|codex] [--ref <branch>] [--vault <name>] [--dry-run] [--force]"
  F_AGENT="${F_AGENT:-${FLEET_DEFAULT_AGENT:-claude}}"
  [[ "$F_AGENT" == claude || "$F_AGENT" == codex ]] || die "Unknown agent '$F_AGENT' (expected claude or codex)"
  F_REF="${F_REF:-${FLEET_REF:-main}}"
  F_VAULT="${F_VAULT:-${FLEET_VAULT:-}}"
  [[ -n "$F_VAULT" ]] || die "No Key Vault: pass --vault or set FLEET_VAULT"
  F_NS="${FLEET_NAMESPACE:-specclaw-fleet}"
  F_IMAGE="$(default_image)"
  [[ "$F_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/:@-]*$ ]] || die "FLEET_IMAGE is not a valid image reference"
  [[ "$F_NS" =~ ^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$ ]] || die "FLEET_NAMESPACE is not a valid namespace name"
  [[ "$F_REF" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$F_REF" != *..* ]] || die "the ref '$F_REF' is not a valid branch name"
  local minutes="${FLEET_DEADLINE_MINUTES:-120}"
  [[ "$minutes" =~ ^[1-9][0-9]{0,3}$ ]] && (( 10#$minutes <= 1440 )) \
    || die "FLEET_DEADLINE_MINUTES must be a whole number from 1 to 1440"
  F_DEADLINE=$(( 10#$minutes * 60 ))
  (( ${F_CHECK_ONLY:-0} )) || parse_pod_inputs
}

check_gates() {
  proposal_approved "$F_CHANGE" || die "$F_CHANGE: proposal is not approved${T_REF_LABEL:+ on $T_REF_LABEL; approve it and push first}"
  [[ -n "$(work_item_id "$F_CHANGE")" ]] || die "$F_CHANGE: no Azure Boards work item (run specclaw-azdo-issue create)"
  local wi rc=0
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$F_CHANGE")" || die "$F_CHANGE: could not read the work item"
  already_handled "$(jq -r '.fields["System.Tags"] // empty' <<<"$wi")"
  gate_owner "$wi" || rc=$?
  case "$rc" in
    0) ;;
    10) echo "$F_CHANGE: not opted in (no fleet:auto tag); skipped, nothing written" >&2; exit 3 ;;
    11) refuse "$F_CHANGE" "work item has no assignee" ;;
    13) refuse "$F_CHANGE" "could not read the work item history to confirm who added fleet:auto" ;;
    *) refuse "$F_CHANGE" "fleet:auto was not added by the assignee $G_ASSIGNEE" ;;
  esac
  F_HASH="$(upn_hash "$G_ASSIGNEE")"
  F_SECRET="$(secret_name "$F_AGENT" "$F_HASH")"
  local rc=0
  F_CREDENTIAL="$(fetch_credential "$F_VAULT" "$F_SECRET")" || rc=$?
  case "$rc" in
    0) ;;
    1) refuse "$F_CHANGE" "assignee has no registered $F_AGENT credential (run specclaw-fleet login --agent $F_AGENT)" ;;
    *) refuse "$F_CHANGE" "could not read Key Vault $F_VAULT (dispatcher access or network), not an assignee problem" ;;
  esac
  if (( ${F_CHECK_ONLY:-0} )); then check_only_busy; fi
}

fleet_dispatch() {
  parse_dispatch_args "$@"
  check_gates
  F_JOB="$(job_name "$F_CHANGE" "$F_AGENT" "$F_HASH")"
  F_SECRET_OBJ="$F_JOB-$(rand_suffix)"
  F_WI="$(work_item_id "$F_CHANGE")"
  F_LABEL="$(label_value "$F_CHANGE")"
  F_REPO="${FLEET_REPO_URL:-$(https_repo_url origin)}" || exit 1
  F_COMMIT="${FLEET_DISPATCH_COMMIT:-$(git -C "$SPECCLAW_DIR/.." rev-parse HEAD)}" || die "Could not resolve the dispatched commit"
  [[ "$F_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "dispatched commit '$F_COMMIT' is not a full 40-character SHA"
  [[ "$F_REPO" =~ ^https://[^@[:space:]]+$ ]] || die "repo URL '$F_REPO' must be https with no credentials"
  [[ -r "$SPECCLAW_DIR/config.yaml" ]] || die "Cannot read $SPECCLAW_DIR/config.yaml"
  F_AZDO_CONFIG="$(awk '/^azdo:[[:space:]]*(#.*)?$/ { on = 1; print; next } on && /^[^[:space:]#]/ { exit } on { print }' \
    "$SPECCLAW_DIR/config.yaml")" || die "Cannot read $SPECCLAW_DIR/config.yaml"
  if (( F_DRY_RUN )); then
    render_job
    echo ---
    render_secret REDACTED "<job-uid>"
    return 0
  fi
  launch_job
}
