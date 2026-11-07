#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster

refused() { (( rc != 0 )) && nothing_applied; }
refused_and_failed() { refused && marked_failed; }

reset_env; echo '{"phases":{"proposal":{"status":"draft"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"
dispatch; rc=$?; check "AC4a unapproved proposal refused" refused

reset_env; : > "$SPECCLAW_DIR/changes/$CHANGE/status.md"
dispatch; rc=$?; check "AC4b no work item refused" refused

reset_env; WI_JSON='{"fields":{"System.Tags":"fleet:auto"}}' dispatch; rc=$?
check "AC4c no assignee refused and marked Failed" refused_and_failed

reset_env; WI_JSON='{"fields":{"System.AssignedTo":{"uniqueName":"a@c.com"},"System.Tags":"fleet:autox"}}' \
  BUILD_REQUESTEDFOREMAIL=other@c.com dispatch; rc=$?
check "AC4d no consent refused and marked Failed" refused_and_failed

reset_env; echo __unset__ > "$KV/claude-token-$H"
dispatch; rc=$?; check "AC4e placeholder credential refused and marked Failed" refused_and_failed

reset_env; JOBS_JSON='{"items":[{"status":{"active":1}}]}' dispatch --agent codex; rc=$?
check "AC4f busy codex assignee refused and marked Failed" refused_and_failed
finish
