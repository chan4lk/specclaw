# shellcheck shell=bash disable=SC2034
wi_has_tag() {
  jq -e --arg t "$2" '.fields["System.Tags"] // "" | ascii_downcase | split(";") | map(gsub("^\\s+|\\s+$"; "")) | index($t) != null' <<<"$1" >/dev/null
}

member_base() {
  local c="$1" m="$2" wi recs rc=0 pr id out newest idx pv=none
  F_CHANGE="$c"
  wi="$(azdo_issue show "$SPECCLAW_DIR" "$c" 2>/dev/null)" && jq -e 'type == "object"' <<<"$wi" >/dev/null 2>&1 || { echo '?'; return; }
  recs="$(azdo_issue records "$SPECCLAW_DIR" "$c" 2>/dev/null)" && jq -e '.records | type == "array"' <<<"$recs" >/dev/null 2>&1 || { echo '?'; return; }
  newest="$(jq -r '.records[0].state // empty' <<<"$recs")"
  idx="$(jq -r '[.records[] | (.pr // "") | test("/pullrequest/[0-9]+$")] | index(true) // -1' <<<"$recs")"
  if (( idx >= 0 )); then
    pr="$(jq -r --argjson i "$idx" '.records[$i].pr' <<<"$recs")"; id="${pr##*/}"
    out="$(azdo_rest "git/pullrequests/$id?api-version=7.1")" && jq -e 'type == "object" and has("status")' <<<"$out" >/dev/null 2>&1 || { echo '?'; return; }
    pv="$(jq -r --arg t "refs/heads/feature/$m" 'if .targetRefName != $t then "stalled" elif .status == "completed" then "merged"
      elif .status == "active" and .mergeStatus == "conflicts" then "conflict" elif .status == "active" then "pr_open" else "stalled" end' <<<"$out")"
    [[ "$pv" == merged ]] && { echo merged; return; }
  fi
  if wi_has_tag "$wi" fleet:refused || { [[ "$newest" == failed ]] && (( idx != 0 )); }; then echo failed; return; fi
  if [[ "$newest" =~ ^(dispatched|running)$ ]] && (( idx != 0 )); then echo running; return; fi
  [[ "$pv" != none ]] && { echo "$pv"; return; }
  wi_has_tag "$wi" fleet:dispatched && { echo stalled; return; }
  gate_owner "$wi" || rc=$?
  case "$rc" in 0) echo pending ;; 10|11|12) echo not-opted-in ;; *) echo '?' ;; esac
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
