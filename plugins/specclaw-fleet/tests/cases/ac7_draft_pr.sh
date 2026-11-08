#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"
posts() { grep -c -- "-X POST" "$TMP/curl.log" 2>/dev/null || true; }
fresh() { rm -f "$TMP/curl.log" "$TMP/pr-body.json"; }

fresh; FAKE_PR=1 run_entry; agent_pr="$(cat "$CALLS")"; agent_posts="$(posts)"
fresh; AGENT_RC=5 run_entry; draft="$(cat "$CALLS")"; body="$(cat "$TMP/pr-body.json" 2>/dev/null)"
fresh; EXISTING_PR=55 AGENT_RC=5 run_entry; reused="$(cat "$CALLS")"; reused_posts="$(posts)"
fresh; PR_POST_FAIL=1 AGENT_RC=5 run_entry; rc=$?; failed="$(cat "$CALLS")"
fresh; ON_BRANCH=main AGENT_RC=5 run_entry; base="$(cat "$CALLS")"; base_posts="$(posts)"

keeps_agent_pr() { [[ "$agent_posts" == 0 ]] && grep -q "pr=https://pr/1 draft=false" <<<"$agent_pr"; }
opens_draft() {
  grep -q "state=pr_open .*pr=https://dev.azure.com/o/p/_git/r/pullrequest/77 draft=true" <<<"$draft" \
    && jq -e '.isDraft == true and .sourceRefName == "refs/heads/specclaw/049-x" and .targetRefName == "refs/heads/main"
      and .workItemRefs == [{"id":"42"}] and (.title | startswith("[draft] 049-x"))' <<<"$body" >/dev/null
}
reuses() { [[ "$reused_posts" == 0 ]] && grep -q "pr=.*/pullrequest/55 draft=true" <<<"$reused"; }
fails_soft() { (( rc == 0 )) && grep -q "state=failed .*pr=none" <<<"$failed"; }
no_base_pr() { [[ "$base_posts" == 0 ]] && grep -q "pr=none" <<<"$base"; }

check "AC7 a PR opened by the agent is kept; no draft is created" keeps_agent_pr
check "AC7 no PR from the agent: the pod opens a draft PR, branch to base, work item linked" opens_draft
check "AC7 an active PR for the branch is reused, never duplicated" reuses
check "AC7 a failed PR call is recorded and does not crash the pod" fails_soft
check "AC7 nothing pushed (HEAD on the base branch): no PR is opened" no_base_pr
finish
