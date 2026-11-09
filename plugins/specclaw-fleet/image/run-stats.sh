# shellcheck shell=bash
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

agent_cost() {
  jq -Rrn '[inputs | fromjson? | objects | select(.type == "result")] | last // empty
    | (["cost_usd", .total_cost_usd], ["turns", .num_turns],
       ["model", (.modelUsage // {} | to_entries | max_by(.value.costUSD // 0) | .key?)])
    | select(.[1] != null) | "\(.[0])=\(.[1])"' "$STATUS/agent.log" 2>/dev/null
}

agent_stats() {
  [[ -n "${AGENT_STARTED:-}" ]] || return 0
  local dir n
  dir="$REPO/.specclaw/$(item_kind)/$FLEET_CHANGE"
  printf '%s\n' "agent_started=$AGENT_STARTED" "agent_ended=$(stamp)" "agent_s=$(( SECONDS - AGENT_T0 ))"
  [[ -f "$STATUS/agent.log" ]] && agent_cost
  local -a rounds=("$dir"/review/round-*.json)
  [[ -e "${rounds[0]}" ]] && echo "review_rounds=${#rounds[@]}" || echo "review_rounds=0"
  n="$(git -C "$REPO" rev-list --count "$AGENT_HEAD..HEAD" 2>/dev/null)"
  [[ "$n" =~ ^[0-9]+$ ]] && echo "agent_commits=$n"
  return 0
}
