#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export SPECCLAW_DIR="$TMP/repo/.specclaw" FLEET_AZDO_ISSUE="$TMP/stub/specclaw-azdo-issue" AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t WI="$TMP/wi" TMP
stub specclaw-azdo-issue '[[ "$1" == records ]] || exit 0; cat "$WI/$3" 2>/dev/null || echo "{\"records\":[]}"'
stub curl 'f="$TMP/api/$(grep -oE "(pullrequests|builds)/[0-9]+" <<<"$*" | tr / -)"; [[ -f "$f" ]] || { printf "\n404"; exit 0; }
[[ "$(cat "$f")" == FAIL500 ]] && { printf "\n500"; exit 0; }; cat "$f"; printf "\n200"'
stub kubectl '[[ -n "${KUBE_FAIL:-}" ]] && exit 1
case "$*" in *"get jobs"*) echo "{\"items\":[{\"metadata\":{\"name\":\"fleet-003-b\",\"creationTimestamp\":\"2026-11-09T12:05:00Z\"},\"status\":{\"active\":1}}]}" ;; *"get pods"*) printf Running ;; esac'
mk() { local d="$SPECCLAW_DIR/changes/$1"; mkdir -p "$d"; echo '{"phases":{"proposal":{"status":"approved"}}}' > "$d/state.json"
  printf '**Feature:** cat\n**Depends on:** %s\n' "$2" > "$d/proposal.md"; printf '**Azure Boards Work Item:** [#%s](https://x)\n' "$3" > "$d/status.md"; }
api() { mkdir -p "$TMP/api"; printf '%s' "$2" > "$TMP/api/$1"; }
reset() {
  rm -rf "$TMP/repo" "$TMP/api" "$WI"; mkdir -p "$WI"; mk 002-a none 11; mk 003-b 002-a 12; mk 004-c none 13
  cat > "$WI/002-a" <<'J'
{"records":[{"at":"2026-11-09T12:00:00.123Z","state":"pr_open","pr":"https://x/pullrequest/11","agent_started":"2026-11-09T11:10:00Z","agent_ended":"2026-11-09T11:40:00Z","agent_s":"1800","cost_usd":"2.5","turns":"40","model":"</script><b>x","review_rounds":"3","agent_commits":"7"},
{"at":"2026-11-09T11:09:00Z","state":"running","claude_fetch_s":"5"},{"at":"2026-11-09T11:05:00Z","state":"dispatched","pipeline_run":"100","job":"fleet-002-a"},
{"at":"2026-11-08T10:00:00Z","state":"failed","exit":"1","review_rounds":"99"},{"at":"2026-11-08T09:00:00Z","state":"dispatched","pipeline_run":"90"}]}
J
  echo '{"records":[{"at":"2026-11-09T12:10:00Z","state":"running","claude_fetch_s":"7"},{"at":"2026-11-09T12:05:00Z","state":"dispatched","pipeline_run":"101","job":"fleet-003-b"}]}' > "$WI/003-b"
  api pullrequests-11 '{"status":"completed","creationDate":"2026-11-09T11:40:00.5Z","closedDate":"2026-11-09T12:00:00Z"}'
  api builds-100 '{"queueTime":"2026-11-09T11:04:00.5Z","startTime":"2026-11-09T11:04:30Z","finishTime":"2026-11-09T11:06:30Z"}'; api builds-101 FAIL500
}
run() { (cd "$TMP/repo" && "$FLEET" report "$@") 2> "$TMP/err"; }
rows=1
want() { local name="$1" filter="$2"; shift 2; local out rc=0; out="$(run --json "$@")" || rc=$?
  (( rc == 0 )) && jq -e "$filter" <<<"$out" >/dev/null 2>&1 || { rows=0; echo "  [$name] rc=$rc $(head -c 400 <<<"$out") $(head -c 200 "$TMP/err")"; }; }
BASE='.version == 1 and .scope == "latest" and ([.rows[].change] == ["002-a", "003-b"])'
A='(.rows[0] | .state == "pr_open" and .pipeline_run == "100" and .queued == "2026-11-09T11:04:00Z" and .agent_s == 1800 and .cost_usd == 2.5 and .review_rounds == 3 and .pr_opened == "2026-11-09T11:40:00Z" and .pr_status == "completed" and .job == "fleet-002-a" and .wave == null)'
B='(.rows[1] | .state == "running" and .phase == "active" and .agent_started == "2026-11-09T12:10:00Z" and .queued == null and .agent_s == null)'
TOT='(.totals | .jobs == 2 and .agent_s == 1800 and .hosted_s == 120 and .review_rounds == 3 and .commits == 7 and .claude_fetch_s == 7 and .cost_usd == 2.5 and .running == 1 and .prs_open == 0 and (.wall_s | type) == "number")'
reset; want "default scope, newest run only, gap fill" "$BASE and $A and $B and $TOT"
reset; api pullrequests-11 FAIL500; want "PR read fails" "$BASE and .rows[0].pr_status == null and .rows[0].pr_opened == null and .rows[0].agent_s == 1800"
reset; api pullrequests-11 '[1]'; api builds-100 '<html>'; want "PR and build answers junk" "$BASE and .rows[0].pr_status == null and .rows[0].queued == null and .totals.hosted_s == 0"
reset; KUBE_FAIL=1 want "cluster unreachable" "$BASE and .rows[1].phase == \"?\""
reset; want "--since drops older runs" '[.rows[].change] == ["003-b"]' --since 2026-11-09T12:00:00Z
reset; want "--feature attaches waves" '.scope == "feature:cat" and ([.rows[] | "\(.change)=\(.wave)"] == ["002-a=1", "003-b=2"])' --feature cat
reset; want "named change without records still gets a row" '[.rows[] | "\(.change)=\(.state)"] == ["004-c=null", "002-a=pr_open"]' 004-c 002-a
reset; ( run --since yesterday >/dev/null ) && { rows=0; echo "  bad --since accepted"; }
json_ok() { (( rows == 1 )); }
reset; table="$(run)"; html="$TMP/r.html"; run --html "$html" --save >/dev/null
table_ok() { grep -q "^CHANGE " <<<"$table" && grep -q "^002-a .*pr_open .*30m .*#11 completed" <<<"$table" && grep -q "API-equivalent estimate" <<<"$table" && grep -q "1 running · 0 PRs open · cost \$2.5" <<<"$table"; }
html_ok() {
  [[ -s "$html" ]] && ! grep -q "__FLEET_REPORT__" "$html" && ! grep -q "</script><b>" "$html" \
    && [[ -z "$(grep -oE "https?://[^\"' <]+" "$html" | grep -v '^https://x/pullrequest/11$')" ]] && grep -q '"rows":\[' "$html"
}
save_ok() { jq -e '.version == 1 and (.rows | length) == 2' "$SPECCLAW_DIR/fleet/report.json" >/dev/null && [[ "$(cat "$SPECCLAW_DIR/fleet/.gitignore")" == "*" ]]; }
check "R054 AC-2 report --json: newest run per change, PR/build/cluster gap fill, totals; failed or junk reads blank fields with exit 0; --since, --feature, named scopes; bad --since refused" json_ok
check "R054 AC-3 report table lists rows and totals with the cost labelled an API-equivalent estimate" table_ok
check "R054 AC-3 report --html is self-contained (no URL but the PR link, </ escaped, data embedded)" html_ok
check "R054 AC-3 report --save writes the v1 snapshot and a folder-local .gitignore" save_ok
finish
