#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
ACTIVE='{"items":[{"status":{"active":1}},{"status":{"succeeded":1}}]}'
DONE='{"items":[{"status":{"succeeded":1}},{"status":{"failed":1}}]}'

reset_env; JOBS_JSON="$ACTIVE" dispatch --agent codex; busy_rc=$?
reset_env; JOBS_JSON="$DONE" dispatch --agent codex; done_rc=$?
reset_env; JOBS_JSON="$ACTIVE" dispatch --agent claude; claude_rc=$?

serialized() { (( busy_rc != 0 && done_rc == 0 )); }
claude_unbounded() { (( claude_rc == 0 )) && ! grep -q "agent=codex," "$CALLS"; }

check "AC6 codex refused while active, allowed once finished" serialized
check "AC6 claude never refused for concurrency" claude_unbounded
finish
