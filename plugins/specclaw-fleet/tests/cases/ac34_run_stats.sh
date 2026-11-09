#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"
RESULT='{"type":"result","total_cost_usd":1.25,"num_turns":40,"modelUsage":{"claude-haiku-5-5":{"costUSD":0.01},"claude-opus-5-5":{"costUSD":1.24}}}'
rows=1
row() {
  local name="$1" want="$2" deny="$3" final
  final="$(grep "state=pr_open" "$CALLS")"
  for w in $want; do grep -qE -- "(^| )$w( |$)" <<<"$final" || { rows=0; echo "  [$name] missing $w in: $final"; }; done
  for d in $deny; do [[ "$d" == *=* ]] || d="$d=[^ ]*"; grep -qE -- " $d( |$)" <<<"$final" && { rows=0; echo "  [$name] unexpected $d"; }; done
  return 0
}
TIMES='agent_started=20[0-9-]{8}T[0-9:]{8}Z agent_ended=20[0-9-]{8}T[0-9:]{8}Z agent_s=[0-9]+'
FAKE_PR=1 AGENT_JSON="$RESULT" ROUNDS=2 run_entry
row "claude json" "$TIMES cost_usd=1.25 turns=40 model=claude-opus-5-5 review_rounds=2 agent_commits=3" ""
FAKE_PR=1 AGENT_JSON="" run_entry
row "text only" "$TIMES review_rounds=0 agent_commits=3" "cost_usd turns model"
FAKE_PR=1 AGENT_JSON='noise line\n{"type":"system","total_cost_usd":9}\n{"type":"result","total_cost_usd":0.5,"num_turns":3}' run_entry
row "mixed lines, no modelUsage" "$TIMES cost_usd=0.5 turns=3" "model"
FAKE_PR=1 AGENT_JSON='{"type":"result","total_cost_usd":' REVLIST=junk run_entry
row "truncated json, unreadable commit count" "$TIMES review_rounds=0" "cost_usd turns model agent_commits"
FAKE_PR=1 AGENT_JSON='{"type":"result","total_cost_usd":"1\\nstate=failed","num_turns":"3","modelUsage":{"m\\npr=evil":{"costUSD":2}}}' run_entry
row "injected newlines and strings" "$TIMES review_rounds=0" "cost_usd turns model pr=evil state=failed"
FAKE_PR=1 AGENT_JSON='{"type":"result","total_cost_usd":0.1,"num_turns":2,"modelUsage":{"bad model; x":{"costUSD":1}}}' run_entry
row "model outside the allowed characters" "$TIMES cost_usd=0.1 turns=2" "model"
ENTRY_AGENT=codex FAKE_PR=1 run_entry
row "codex" "$TIMES" "cost_usd turns model"
CLONE_FAIL=1 run_entry
pre_agent_clean() { ! grep -q "agent_started=" "$CALLS"; }
stats_ok() { (( rows == 1 )); }
check "R054 AC-1 final pod record carries agent times, review rounds and agent commits; cost, turns and model only from a readable result object (claude json, text, mixed lines, truncated, injected newlines, bad model, codex); only allow-listed key=value lines reach the record" stats_ok
check "R054 AC-1 a run that fails before the agent records no agent stats" pre_agent_clean
finish
