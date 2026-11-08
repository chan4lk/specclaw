# shellcheck shell=bash
optin_plan() {
  local wi who tags
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$1")" || { echo "$1: could not read the work item"; return 1; }
  who="$(jq -r '.fields["System.AssignedTo"].uniqueName // empty' <<<"$wi")"
  tags="$(jq -r '.fields["System.Tags"] // empty' <<<"$wi")"
  if [[ -n "$who" && "$(lower "$who")" != "$(lower "$2")" ]]; then
    echo "$1: refused: assigned to $who; only they can opt in"; return 4
  fi
  if [[ -n "$who" ]] && has_auto_tag "$tags"; then echo "$1: already opted in"; return 0; fi
  if [[ -n "$who" ]]; then echo "$1: would add fleet:auto as $2"; else echo "$1: would assign to $2 and add fleet:auto"; fi
}

optin_one() {
  local rc=0
  [[ -d "$SPECCLAW_DIR/changes/$1" ]] || { echo "$1: no such change in $SPECCLAW_DIR/changes" >&2; return 1; }
  [[ -n "$(work_item_id "$1")" ]] || { echo "$1: no work item; run: specclaw-fleet trigger $1 --create" >&2; return 1; }
  if (( O_DRY )); then optin_plan "$1" "$2"; return; fi
  azdo_issue optin "$SPECCLAW_DIR" "$1" fleet:auto "$2" >/dev/null 2>"$FLEET_TMPDIR/optin.err" || rc=$?
  case "$rc" in
    0) echo "$1: opted in (#$(work_item_id "$1"), assigned to $2, fleet:auto)" ;;
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
  local me c rc worst=0
  me="$(azdo_issue whoami "$SPECCLAW_DIR" "${changes[0]}" 2>/dev/null | jq -r '.upn // empty')"
  [[ -n "$me" ]] || die "could not read the identity behind AZDO_TOKEN (check .specclaw/.env)"
  for c in "${changes[@]}"; do
    rc=0; optin_one "$c" "$me" || rc=$?
    (( rc > worst )) && worst=$rc
  done
  return "$worst"
}
