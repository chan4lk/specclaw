# shellcheck shell=bash disable=SC2034
optin_decide() {
  local wi rc=0
  F_CHANGE="$1"
  O_ACTION=error O_WHY="could not read the work item history"
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$1")" && jq -e 'type == "object"' <<<"$wi" >/dev/null 2>&1 || { O_WHY="could not read the work item"; return; }
  O_WHO="$(jq -r '.fields["System.AssignedTo"].uniqueName // empty' <<<"$wi")"
  if [[ -n "$O_WHO" && "$(lower "$O_WHO")" != "$(lower "$2")" ]]; then O_ACTION=refuse; return; fi
  gate_owner "$wi" || rc=$?
  case "$rc" in 0) O_ACTION=opted ;; 10) O_ACTION=add ;; 11|12) O_ACTION=readd ;; 13) ;; *) O_WHY="unexpected consent check result $rc" ;; esac
}

optin_one() {
  local rc=0
  [[ -d "$SPECCLAW_DIR/changes/$1" ]] || { echo "$1: no such change in $SPECCLAW_DIR/changes" >&2; return 1; }
  [[ -n "$(work_item_id "$1")" ]] || { echo "$1: no work item; run: specclaw-fleet trigger $1 --create" >&2; return 1; }
  optin_decide "$1" "$2"
  case "$O_ACTION" in
    refuse) echo "$1: refused: assigned to $O_WHO; only they can opt in" >&2; return 4 ;;
    opted) echo "$1: already opted in by $2"; return 0 ;;
    error) echo "$1: $O_WHY" >&2; return 1 ;;
  esac
  if (( O_DRY )); then
    local how="assign to $2 and "; [[ -n "$O_WHO" ]] && how="keep the assignment and "
    echo "$1: would $how$([[ $O_ACTION == readd ]] && echo "re-add fleet:auto as $2 (it was not added by the assignee)" || echo "add fleet:auto as $2")"
    return 0
  fi
  azdo_issue optin "$SPECCLAW_DIR" "$1" fleet:auto "$2" >/dev/null 2>"$FLEET_TMPDIR/optin.err" || rc=$?
  case "$rc" in
    0) echo "$1: opted in (#$(work_item_id "$1"), assigned to $2, fleet:auto added by $2)" ;;
    4) echo "$1: refused: work item is assigned to someone else; only they can opt in" >&2 ;;
    *) echo "$1: could not opt in: $(head -n1 "$FLEET_TMPDIR/optin.err")" >&2 ;;
  esac
  return "$rc"
}

fleet_optin() {
  local -a changes=()
  O_DRY=0
  while (($#)); do
    case "$1" in --dry-run) O_DRY=1 ;; -*) die "Unknown flag: $1" ;; *) changes+=("$1") ;; esac
    shift
  done
  (( ${#changes[@]} )) || die "Usage: specclaw-fleet optin <change>... [--dry-run]"
  load_azdo_env
  local me c rc worst=0 errored=0
  me="$(azdo_issue whoami "$SPECCLAW_DIR" "${changes[0]}" 2>/dev/null | jq -r '.upn // empty')"
  [[ -n "$me" ]] || die "could not read the identity behind AZDO_TOKEN (check .specclaw/.env)"
  for c in "${changes[@]}"; do
    rc=0; optin_one "$c" "$me" || rc=$?
    (( rc == 1 )) && errored=1
    (( rc > worst )) && worst=$rc
  done
  (( errored )) && return 1
  return "$worst"
}
