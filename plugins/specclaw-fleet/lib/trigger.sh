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
  F_CHANGE="$T_CHANGE" T_AGENT="${FLEET_DEFAULT_AGENT:-claude}"
  load_azdo_env
}

trigger_ref_approved() {
  [[ -n "${T_CHANGE:-}" ]] || T_CHANGE="$F_CHANGE"
  local remote="${FLEET_REMOTE:-origin}" ref="${FLEET_REF:-main}" root="$SPECCLAW_DIR/.." status
  git -C "$root" fetch -q "$remote" "$ref" 2>/dev/null || die "could not fetch $remote/$ref"
  status="$(git -C "$root" show "FETCH_HEAD:$(basename "$SPECCLAW_DIR")/changes/$T_CHANGE/state.json" 2>/dev/null \
    | jq -r '.phases.proposal.status // empty')"
  [[ "$status" == approved ]] || die "$T_CHANGE: proposal is not approved on $remote/$ref; approve it and push first"
}

trigger_work_item() {
  [[ -n "$(work_item_id "$T_CHANGE")" ]] && return 0
  (( T_CREATE )) || die "$T_CHANGE: no Azure Boards work item; pass --create to create one"
  azdo_issue create "$SPECCLAW_DIR" "$T_CHANGE" >&2 || die "$T_CHANGE: could not create the work item"
  echo "$T_CHANGE: created work item #$(work_item_id "$T_CHANGE"); assign it, have the assignee add fleet:auto, then re-run trigger" >&2
  exit 3
}

trigger_codex_busy() {
  [[ "$T_AGENT" == codex ]] || return 0
  local state
  if ! state="$(kubectl -n "$F_NS" --request-timeout=10s get job "fleet-codex-$F_HASH" -o json 2>&1)"; then
    grep -q NotFound <<<"$state" && return 0
    T_BUSY_CHECK="not-run (no cluster access here; dispatch will report)"; return 0
  fi
  jq -e '(.status.active // 0) > 0' <<<"$state" >/dev/null && { echo "$T_CHANGE: assignee's codex slot is busy; retry once it finishes" >&2; exit 5; }
  return 0
}

fleet_trigger() {
  parse_trigger_args "$@"
  if (( T_RETRY )); then
    azdo_issue untag "$SPECCLAW_DIR" "$T_CHANGE" fleet:dispatched >&2 || die "could not clear fleet:dispatched"
    azdo_issue untag "$SPECCLAW_DIR" "$T_CHANGE" fleet:refused >&2 || die "could not clear fleet:refused"
  fi
  trigger_work_item
  F_CHECK_ONLY=1 T_BUSY_CHECK="done"
  parse_dispatch_args "$T_CHANGE" --agent "$T_AGENT"
  check_gates
  trigger_codex_busy
  F_CHECK_ONLY=0
  if (( T_DIRECT )); then fleet_dispatch "$T_CHANGE" --agent "$T_AGENT"; return; fi
  local -a a; mapfile -t a < <(azdo_args)
  local run
  run="$(az pipelines run --name "${FLEET_PIPELINE:-specclaw-fleet}" --branch "${FLEET_REF:-main}" "${a[@]}" \
    --parameters "change=$T_CHANGE" "agent=$T_AGENT" --query id -o tsv)" || die "$T_CHANGE: could not queue pipeline ${FLEET_PIPELINE:-specclaw-fleet}"
  jq -nc --arg r "$run" --arg w "$(work_item_id "$T_CHANGE")" --arg c "$T_CHANGE" --arg a "$T_AGENT" --arg b "$T_BUSY_CHECK" \
    '{ok: true, mode: "queued", run: $r, change: $c, agent: $a, work_item: $w, codex_busy_check: $b,
      note: "gates passed here; the dispatch outcome is recorded on the work item"}'
}
