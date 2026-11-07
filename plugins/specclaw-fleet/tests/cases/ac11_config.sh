#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
cfg="$SPECCLAW_DIR/config.yaml"

reset_env; rm "$cfg"; dispatch; absent_rc=$?; absent_out="$(cat "$TMP/out")"
reset_env; chmod 000 "$cfg"; dispatch; unreadable_rc=$?; chmod 644 "$cfg"
reset_env; stub python3 'exit 127'; dispatch; nopy_rc=$?; rm "$TMP/stub/python3"
reset_env; printf 'fleet:  # fleet\n  vault: v\nazdo:   # boards\n  fleet_states:\n    failed: Failed\n' > "$cfg"
dispatch --dry-run; comment_rc=$?

fails_closed() {
  (( absent_rc != 0 && unreadable_rc != 0 && nopy_rc != 0 )) && grep -q "Cannot read" <<<"$absent_out" && nothing_applied
}
one_header_rule() {
  (( comment_rc == 0 )) && grep -q 'FLEET_AZDO_CONFIG, value: "azdo:.*failed: Failed' "$TMP/out"
}

check "AC11 missing, unreadable or unparsable config stops dispatch" fails_closed
check "AC11 value and block reads share one header rule (trailing comments)" one_header_rule
finish
