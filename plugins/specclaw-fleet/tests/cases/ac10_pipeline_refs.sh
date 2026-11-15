#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
APPROVED='{"phase":"proposal","phases":{"proposal":{"status":"approved"}}}'
ok=1
for template in dispatch.yml dispatch-hosted.yml; do
  for row in "refs/heads/main|main" "refs/heads/feature/fleet-x|feature/fleet-x" "main|ERR" "|ERR" "refs/tags/v1|ERR" "refs/pull/1/merge|ERR" "refs/heads/|ERR"; do
    out="$(PIPELINE_FILE="$template" FLEET_REF="${row%%|*}" bash -c '
      source "$1/tests/lib/harness.sh"; source "$1/tests/lib/pipeline-env.sh"
      export FLEET_REF="$2"; rm -f "$TMP/refs"; run_with_state 049-x "$3"; echo "rc=$?"; cat "$TMP/refs" 2>/dev/null' _ "$FLEET_ROOT" "${row%%|*}" "$APPROVED")"
    want="${row#*|}"
    if [[ "$want" == ERR ]]; then [[ "$out" == *"rc=1"* && "$out" != *"ref="* ]] || { ok=0; echo "  $template ${row%%|*}: expected failure, got: $out"; }
    else [[ "$out" == *"rc=0"* && "$out" == *"ref=$want"* ]] || { ok=0; echo "  $template ${row%%|*}: got: $out"; }; fi
  done
done
refs_ok() { (( ok == 1 )); }
check "FR10 both templates pass branch refs as full names and fail closed on bare, empty, tag and PR refs" refs_ok
finish
