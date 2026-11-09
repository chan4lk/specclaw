# shellcheck shell=bash disable=SC2034
member_base() {
  local c="$1" m="$2" wi recs rc=0 consent pr id out branch
  F_CHANGE="$c"
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$c" 2>/dev/null)" && jq -e 'type == "object"' <<<"$wi" >/dev/null 2>&1 || { echo '?'; return; }
  recs="$(azdo_issue records "$SPECCLAW_DIR" "$c" 2>/dev/null)" || recs='{"records":[]}'
  [[ "$(jq -r '.records[0].state // empty' <<<"$recs")" =~ ^(dispatched|running)$ ]] && { echo running; return; }
  pr="$(jq -r '[.records[]? | select((.pr // "") | test("/pullrequest/[0-9]+$"))][0].pr // empty' <<<"$recs")"
  if [[ -n "$pr" ]]; then
    id="${pr##*/}"; out="$(azdo_rest "git/pullrequests/$id?api-version=7.1")" && jq -e 'type == "object" and has("status")' <<<"$out" >/dev/null 2>&1 \
      || { echo '?'; return; }
    case "$(jq -r --arg t "refs/heads/feature/$m" 'if .targetRefName != $t then "other"
      elif .status == "completed" then "merged" elif .status == "active" and .mergeStatus == "conflicts" then "conflict"
      elif .status == "active" then "pr_open" else "closed" end' <<<"$out" 2>/dev/null)" in
      merged) echo merged; return ;; conflict) echo conflict; return ;; pr_open) echo pr_open; return ;;
    esac
  fi
  branch="$(jq -r '.branch // empty' "$(item_dir "$c")/state.json" 2>/dev/null)"
  if [[ -n "$branch" ]] && git -C "$SPECCLAW_DIR/.." merge-base --is-ancestor "origin/$branch" "origin/feature/$m" 2>/dev/null; then echo merged; return; fi
  if jq -e '.fields["System.Tags"] // "" | ascii_downcase | test("(^|;)\\s*fleet:refused\\s*(;|$)")' <<<"$wi" >/dev/null \
    || [[ "$(jq -r '.records[0].state // empty' <<<"$recs")" == failed ]]; then echo failed; return; fi
  gate_owner "$wi" || rc=$?
  case "$rc" in 0) consent=ok ;; 10|11|12) consent=no ;; *) consent=unknown ;; esac
  case "$consent" in ok) echo pending ;; no) echo not-opted-in ;; *) echo '?' ;; esac
}

feature_states() {
  local m="$1" wave c deps d s
  local -A base=()
  local waves; waves="$(feature_waves "$m")" || exit 1
  while IFS=$'\t' read -r wave c; do base[$c]="$(member_base "$c" "$m")"; done <<<"$waves"
  while IFS=$'\t' read -r wave c; do
    s="${base[$c]}"; deps="$(change_deps "$c" | paste -sd, -)"
    if [[ "$s" == pending ]]; then
      s=ready; for d in ${deps//,/ }; do [[ "${base[$d]}" == merged ]] || s=waiting; done
    fi
    jq -nc --arg c "$c" --argjson w "$wave" --arg s "$s" --arg d "$deps" '{change: $c, wave: $w, state: $s, depends_on: ($d | split(",") | map(select(. != "")))}'
  done <<<"$waves" | jq -sc '.'
}
