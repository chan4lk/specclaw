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

trigger_pushed_tree() {
  local remote="${FLEET_REMOTE:-origin}" ref="${FLEET_REF:-main}" root="$SPECCLAW_DIR/.." sc tree f
  sc="$(basename "$SPECCLAW_DIR")"
  git -C "$root" fetch -q "$remote" "$ref" 2>/dev/null || die "could not fetch $remote/$ref"
  tree="$FLEET_TMPDIR/pushed/$sc"
  mkdir -p "$tree/changes/$T_CHANGE"
  git -C "$root" show "FETCH_HEAD:$sc/config.yaml" > "$tree/config.yaml" 2>/dev/null || rm -f "$tree/config.yaml"
  for f in state.json status.md; do
    git -C "$root" show "FETCH_HEAD:$sc/changes/$T_CHANGE/$f" > "$tree/changes/$T_CHANGE/$f" 2>/dev/null || rm -f "$tree/changes/$T_CHANGE/$f"
  done
  export FLEET_DISPATCH_COMMIT FLEET_REPO_URL
  FLEET_DISPATCH_COMMIT="$(git -C "$root" rev-parse FETCH_HEAD)"
  FLEET_REPO_URL="$(git -C "$root" remote get-url "$remote" | sed -E 's#://[^@/]+@#://#')"
  T_LOCAL_DIR="$SPECCLAW_DIR" SPECCLAW_DIR="$tree" T_REF_LABEL="$remote/$ref"
}

trigger_work_item() {
  [[ -n "$(work_item_id "$T_CHANGE")" ]] && return 0
  (( T_CREATE )) || die "$T_CHANGE: no Azure Boards work item; pass --create to create one"
  azdo_issue create "$T_LOCAL_DIR" "$T_CHANGE" >&2 || die "$T_CHANGE: could not create the work item"
  echo "$T_CHANGE: created work item #$(SPECCLAW_DIR="$T_LOCAL_DIR" work_item_id "$T_CHANGE"); commit and push status.md, assign the item, have the assignee add fleet:auto, then re-run trigger" >&2
  exit 3
}

fleet_trigger() {
  parse_trigger_args "$@"
  T_BUSY_CHECK="done"
  trigger_pushed_tree
  proposal_approved "$T_CHANGE" || die "$T_CHANGE: proposal is not approved on $T_REF_LABEL; approve it and push first"
  trigger_work_item
  local -a force=()
  (( T_RETRY )) && force=(--force)
  F_CHECK_ONLY=1
  parse_dispatch_args "$T_CHANGE" --agent "$T_AGENT" ${force[@]+"${force[@]}"}
  check_gates
  F_CHECK_ONLY=0
  if (( T_RETRY )); then
    azdo_issue untag "$SPECCLAW_DIR" "$T_CHANGE" fleet:dispatched >&2 || die "could not clear fleet:dispatched"
    azdo_issue untag "$SPECCLAW_DIR" "$T_CHANGE" fleet:refused >&2 || die "could not clear fleet:refused"
  fi
  if (( T_DIRECT )); then fleet_dispatch "$T_CHANGE" --agent "$T_AGENT"; return; fi
  local -a a; mapfile -t a < <(azdo_args)
  local run
  run="$(az pipelines run --name "${FLEET_PIPELINE:-specclaw-fleet}" --branch "${FLEET_REF:-main}" "${a[@]}" \
    --parameters "change=$T_CHANGE" "agent=$T_AGENT" --query id -o tsv)" || die "$T_CHANGE: could not queue pipeline ${FLEET_PIPELINE:-specclaw-fleet}"
  jq -nc --arg r "$run" --arg w "$(work_item_id "$T_CHANGE")" --arg c "$T_CHANGE" --arg a "$T_AGENT" --arg b "$T_BUSY_CHECK" \
    '{ok: true, mode: "queued", run: $r, change: $c, agent: $a, work_item: $w, codex_busy_check: $b,
      note: "gates passed here; the dispatch outcome is recorded on the work item"}'
}
