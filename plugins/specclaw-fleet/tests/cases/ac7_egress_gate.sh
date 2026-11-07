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
finish
