#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
cfg="$SPECCLAW_DIR/config.yaml"
stopped() { (( rc != 0 )) && nothing_applied && grep -q "$1" "$TMP/out"; }
stopped_unreadable() { stopped "Cannot read"; }
stopped_parse() { stopped "Could not parse"; }
stopped_deadline() { stopped "deadline_minutes must be a whole number"; }
ran() { (( rc == 0 )); }

reset_env; rm "$cfg"; dispatch; rc=$?; check "AC11 absent config.yaml stops dispatch" stopped_unreadable
if (( $(id -u) != 0 )); then
  reset_env; chmod 000 "$cfg"; dispatch; rc=$?; chmod 644 "$cfg"
  check "AC11 unreadable config.yaml stops dispatch" stopped_unreadable
fi
reset_env; stub python3 'exit 127'; dispatch; rc=$?; rm "$TMP/stub/python3"
check "AC11 config parser unavailable stops dispatch" stopped_parse

for minutes in abc -5 1.5; do
  reset_env; printf '  deadline_minutes: %s\n' "$minutes" >> "$cfg"; dispatch; rc=$?
  check "AC11 deadline_minutes '$minutes' refused" stopped_deadline
done
reset_env; printf '  deadline_minutes: ""\n' >> "$cfg"; dispatch; rc=$?
check "AC11 empty deadline_minutes falls back to the default" ran

reset_env; printf 'fleet:  # fleet\n  vault: v\nazdo:   # boards\n  fleet_states:\n    failed: Failed\n' > "$cfg"
dispatch --dry-run; rc=$?
one_header_rule() { (( rc == 0 )) && grep -q 'FLEET_AZDO_CONFIG, value: "azdo:.*failed: Failed' "$TMP/out"; }
check "AC11 value and block reads share one header rule (trailing comments)" one_header_rule
finish
