# shellcheck shell=bash disable=SC2034
parse_trigger_args() {
  T_CHANGE="" T_RETRY=0 T_DIRECT=0 T_CREATE=0
  while (($#)); do
    case "$1" in
      --retry) T_RETRY=1 ;;
      --direct) T_DIRECT=1 ;;
      --create) T_CREATE=1 ;;
      -*) die "Unknown flag: $1" ;;
      *) T_CHANGE="$1" ;;
    esac
    shift
  done
  [[ -n "$T_CHANGE" ]] || die "Usage: specclaw-fleet trigger <change> [--retry] [--direct] [--create]"
  F_CHANGE="$T_CHANGE"
  if [[ -z "${AZDO_ORG:-}" && -f "$SPECCLAW_DIR/.env" ]]; then set -a; . "$SPECCLAW_DIR/.env"; set +a; fi
}

trigger_work_item() {
  [[ -n "$(work_item_id "$T_CHANGE")" ]] && return 0
  (( T_CREATE )) || die "$T_CHANGE: no Azure Boards work item; pass --create to create one"
  azdo_issue create "$SPECCLAW_DIR" "$T_CHANGE" >&2 || die "$T_CHANGE: could not create the work item"
}

trigger_gates() {
  proposal_approved "$T_CHANGE" || die "$T_CHANGE: proposal is not approved; approve it through the specclaw lifecycle first"
  trigger_work_item
  local wi assignee tags tagger rc=0 agent="${FLEET_DEFAULT_AGENT:-claude}"
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$T_CHANGE")" || die "$T_CHANGE: could not read the work item"
  assignee="$(jq -r '.fields["System.AssignedTo"].uniqueName // empty' <<<"$wi")"
  tags="$(jq -r '.fields["System.Tags"] // empty' <<<"$wi")"
  [[ -n "$assignee" ]] || die "$T_CHANGE: work item #$(work_item_id "$T_CHANGE") has no assignee; assign the person whose plan will run it"
  has_auto_tag "$tags" || consent_missing "$assignee"
  tagger="$(auto_tagged_by)" || die "$T_CHANGE: could not read the work item history"
  [[ "$(lower "$tagger")" == "$(lower "$assignee")" ]] || consent_missing "$assignee"
  [[ -n "${FLEET_VAULT:-}" ]] || die "No Key Vault: set FLEET_VAULT"
  fetch_credential "$FLEET_VAULT" "$(secret_name "$agent" "$(upn_hash "$assignee")")" >/dev/null || rc=$?
  case "$rc" in
    0) ;;
    1) die "$T_CHANGE: $assignee has no registered $agent credential; they run: specclaw-fleet login --agent $agent" ;;
    *) die "$T_CHANGE: could not read Key Vault $FLEET_VAULT" ;;
  esac
}

consent_missing() {
  echo "ERROR: $T_CHANGE: $1 must add the fleet:auto tag to work item #$(work_item_id "$T_CHANGE") themselves" >&2
  exit 4
}

fleet_trigger() {
  parse_trigger_args "$@"
  trigger_gates
  if (( T_RETRY )); then
    azdo_issue untag "$SPECCLAW_DIR" "$T_CHANGE" fleet:dispatched >&2 || die "could not clear fleet:dispatched"
    azdo_issue untag "$SPECCLAW_DIR" "$T_CHANGE" fleet:refused >&2 || die "could not clear fleet:refused"
  fi
  if (( T_DIRECT )); then fleet_dispatch "$T_CHANGE"; return; fi
  local -a a; mapfile -t a < <(azdo_args)
  local run
  run="$(az pipelines run --name "${FLEET_PIPELINE:-specclaw-fleet}" --branch "${FLEET_REF:-main}" "${a[@]}" --query id -o tsv)" \
    || die "$T_CHANGE: could not queue pipeline ${FLEET_PIPELINE:-specclaw-fleet}"
  jq -nc --arg r "$run" --arg w "$(work_item_id "$T_CHANGE")" '{ok: true, mode: "pipeline", run: $r, work_item: $w}'
}
