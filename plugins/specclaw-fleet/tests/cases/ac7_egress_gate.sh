#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"

for gate in proxy-down direct-open; do
  GATE="$gate" run_entry; rc=$?
  held() {
    (( rc == 0 )) && [[ "$(cat "$TMP/status/exit")" == 2 ]] && grep -q "exit=egress-not-ready" "$CALLS" \
      && ! grep -q "git clone" "$CALLS" && [[ ! -s "$TMP/leaked" ]]
  }
  check "AC7 egress gate ($gate): no clone, no agent, Failed egress-not-ready" held
done
GATE="" FAKE_PR=1 run_entry; rc=$?
passes() { (( rc == 0 )) && [[ "$(cat "$TMP/status/exit")" == 0 ]] && grep -q "git clone" "$CALLS"; }
check "AC7 egress gate open (proxy up, direct blocked): run proceeds" passes
log_redacted() {
  grep -q "agent says hi" "$TMP/out" && ! grep -q "SECRETTOKENVALUE" "$TMP/out" && ! grep -q "abcdefghijklmnopqrstuvwxyz0123456789" "$TMP/out"
}
check "AC7 agent log tail reaches the container log with tokens redacted" log_redacted
AGENT_RC=5 run_entry; failed_calls="$(cat "$CALLS")"
ON_BRANCH=main AGENT_RC=5 run_entry; base_calls="$(cat "$CALLS")"
work_survives() {
  grep -q "git -C .* push -q -u origin HEAD" <<<"$failed_calls" && grep -q "state=failed exit=5 branch=specclaw/049-x" <<<"$failed_calls" \
    && ! grep -q " push " <<<"$base_calls"
}
check "AC7 a failed run still pushes the change branch (never the base branch)" work_survives
GATE="" run_entry; token_file="$(stat -f '%Lp' "$TMP/home/.fleet/claude-token" 2>/dev/null || stat -c '%a' "$TMP/home/.fleet/claude-token")"
printf '#!/usr/bin/env bash\necho "nested-token=${CLAUDE_CODE_OAUTH_TOKEN:-none}"\n' > "$TMP/real-claude"; chmod +x "$TMP/real-claude"
nested="$(env -u CLAUDE_CODE_OAUTH_TOKEN HOME="$TMP/home" FLEET_REAL_CLAUDE="$TMP/real-claude" "$FLEET_ROOT/image/bin/claude" -p x)"
keep="$(CLAUDE_CODE_OAUTH_TOKEN=caller HOME="$TMP/home" FLEET_REAL_CLAUDE="$TMP/real-claude" "$FLEET_ROOT/image/bin/claude" -p x)"
nested_auth() { [[ "$token_file" == 600 && "$nested" == nested-token=oat-token && "$keep" == nested-token=caller ]]; }
check "AC7 a nested claude with no token env picks up the pod token (0600 file); an explicit token wins" nested_auth
REMOTE_BRANCH=specclaw/049-x run_entry; resume_calls="$(cat "$CALLS")"
REMOTE_BRANCH=specclaw/1049-x run_entry; other_calls="$(cat "$CALLS")"
resumes() {
  grep -q "checkout -q -B specclaw/049-x origin/specclaw/049-x" <<<"$resume_calls" && ! grep -q "checkout" <<<"$other_calls"
}
check "AC7 an existing remote change branch is resumed; a lookalike name is not" resumes
finish
