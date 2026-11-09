# shellcheck shell=bash
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

agent_cost() {
  jq -Rrn '[inputs | fromjson? | objects | select(.type == "result")] | last // empty
    | (["cost_usd", (.total_cost_usd | numbers)], ["turns", (.num_turns | numbers)],
       ["model", (.modelUsage | objects | to_entries | max_by(.value.costUSD | numbers // 0) | .key | strings | select(test("^[A-Za-z0-9._:-]{1,80}$")))])
    | select(length == 2) | "\(.[0])=\(.[1])"' "$STATUS/agent.log" 2>/dev/null
}

STAT_LINE='^(agent_started|agent_ended|agent_s|cost_usd|turns|model|review_rounds|agent_commits)=[A-Za-z0-9._:+-]{1,80}$'

safe_stats() {
  local line
  while IFS= read -r line; do [[ "$line" =~ $STAT_LINE ]] && printf '%s\n' "$line"; done < <(agent_stats)
  return 0
}

round_count() {
  local -a rounds=("$REPO/.specclaw/$(item_kind)/$FLEET_CHANGE"/review/round-*.json)
  if [[ -e "${rounds[0]}" ]]; then echo "${#rounds[@]}"; else echo 0; fi
}

agent_stats() {
  [[ -n "${AGENT_STARTED:-}" ]] || return 0
  local n
  printf '%s\n' "agent_started=$AGENT_STARTED" "agent_ended=$(stamp)" "agent_s=$(( SECONDS - AGENT_T0 ))"
  [[ -f "$STATUS/agent.log" ]] && agent_cost
  n=$(( $(round_count) - ${AGENT_ROUNDS0:-0} ))
  echo "review_rounds=$(( n > 0 ? n : 0 ))"
  n="$(git -C "$REPO" rev-list --count "$AGENT_HEAD..HEAD" 2>/dev/null)"
  [[ "$n" =~ ^[0-9]+$ ]] && echo "agent_commits=$n"
  return 0
}
