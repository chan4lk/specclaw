#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export SPECCLAW_DIR="$TMP/repo/.specclaw" FLEET_AZDO_ISSUE="$TMP/stub/specclaw-azdo-issue" AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t WI="$TMP/wi" TMP
stub specclaw-azdo-issue '
d="$WI/$3"
case "$1" in
  show) [[ -f "$d/noread" ]] && exit 1; jq -nc --arg t "$(cat "$d/tags")" "{fields: {\"System.State\": \"Doing\", \"System.Tags\": \$t, \"System.AssignedTo\": {uniqueName: \"alice@contoso.com\"}}}" ;;
  records) [[ -f "$d/noread" ]] && exit 1
    n=$(( $(cat "$d/n" 2>/dev/null || echo 0) + 1 )); echo $n > "$d/n"
    f="$d/records"; [[ -f "$d/records.$n" ]] && f="$d/records.$n"; cat "$f" ;;
esac'
stub kubectl '
[[ "$1" == --context ]] && shift 2
[[ -n "${KUBE_DOWN:-}" ]] && exit 1
case "$*" in
  *"get jobs -l specclaw.fleet/change=002-a"*) echo "{\"items\":[{\"metadata\":{\"name\":\"fleet-002-old\",\"creationTimestamp\":\"2026-11-08T01:00:00Z\"},\"status\":{\"failed\":1}},{\"metadata\":{\"name\":\"fleet-002-new\",\"creationTimestamp\":\"2026-11-08T03:00:00Z\"},\"status\":{\"active\":1}}]}" ;;
  *"get jobs"*) echo "{\"items\":[]}" ;;
  *"get pods -l job-name=fleet-002-new"*) printf Running ;;
esac'
stub curl 'case "$*" in
  *"build/definitions?name=specclaw-fleet"*) echo "{\"value\":[{\"id\":44,\"name\":\"specclaw-fleet\"}]}" ;;
  *"/pipelines/44/runs"*) echo "{\"value\":[{\"id\":2437,\"state\":\"completed\",\"result\":\"succeeded\"}]}" ;;
esac'
mk() {
  mkdir -p "$SPECCLAW_DIR/changes/$1" "$WI/$1"; printf '%s' "$2" > "$WI/$1/tags"; printf '%s' "$3" > "$WI/$1/records"
  echo "{\"phases\":{\"proposal\":{\"status\":\"$4\"}}}" > "$SPECCLAW_DIR/changes/$1/state.json"
  [[ "$5" == nowi ]] || printf '**Azure Boards Work Item:** [#%s](https://x)\n' "$5" > "$SPECCLAW_DIR/changes/$1/status.md"
}
REC() { printf '{"work_item":"x","records":[{"at":"%s","state":"%s","exit":"%s","pr":"%s","draft":"%s"}]}' "$@"; }
reset() {
  rm -rf "$TMP/repo" "$WI"
  mk 002-a "specclaw; fleet:auto; fleet:dispatched" "$(REC 2026-11-08T03:10:00Z pr_open 0 https://x/pr/1 true)" approved 209
  mk 003-b "specclaw; fleet:auto" "$(REC 2026-11-07T10:00:00Z failed 3 '' '')" approved 210
  mk 004-c "specclaw" '{"records":[]}' approved 211
  mk 005-d "" "" approved nowi
  mk 006-e "specclaw" '{"records":[]}' draft 212
  : > "$CALLS"
}
st() { (cd "$TMP/repo" && "$FLEET" status "$@") > "$TMP/out" 2>&1; }
reset; st --json --since 2026-11-08T00:00:00Z; j="$(cat "$TMP/out")"
fields_ok() {
  jq -e '.pipeline.run == 2437 and (.changes | map(.change) == ["002-a","003-b","004-c","005-d"])' <<<"$j" >/dev/null \
    && jq -e '.changes[0] | .work_item == "209" and .state == "Doing" and .tags == ["auto","dispatched"] and .record.state == "pr_open" and .record.draft == "true" and .cluster.job == "fleet-002-new" and .cluster.phase == "active" and .cluster.pod == "Running" and .terminal' <<<"$j" >/dev/null \
    && jq -e '.changes[1].record.state == "waiting" and (.changes[1].terminal | not)' <<<"$j" >/dev/null \
    && jq -e '.changes[2].terminal and .changes[2].tags == [] and .changes[2].record.state == "not-opted-in" and .changes[3].note == "no work item"' <<<"$j" >/dev/null
}
check "R053 AC-4 status: pipeline header, approved changes by default, item/state/assignee/tags/newest record/newest Job; records before --since are waiting" fields_ok
reset; touch "$WI/002-a/noread"; KUBE_DOWN=1 st --json 002-a; u="$(cat "$TMP/out")"
unknown_not_guessed() { jq -e '.changes[0] | .state == "?" and .assignee == "?" and .record.state == "?" and .cluster.job == "?" and (.terminal | not)' <<<"$u" >/dev/null; }
check "R053 AC-4 unreadable AzDO or cluster shows ? and is never terminal" unknown_not_guessed
reset; REC 2026-11-08T00:00:00.500Z dispatched '' '' '' > "$WI/004-c/records"; printf 'specclaw; fleet:auto' > "$WI/004-c/tags"
st --json 004-c --since 2026-11-08T00:00:00Z; same_second="$(jq -r '.changes[0].record.state' "$TMP/out")"
reset; REC 2026-11-09T00:00:00Z refused '' '' '' > "$WI/002-a/records"; printf 'specclaw; fleet:auto; fleet:refused' > "$WI/003-b/tags"
st 002-a 003-b --watch 0 --since 2026-11-08T00:00:00Z; refused_rc=$?; refused_frames="$(grep -c '^--- ' "$TMP/out")"
reset; REC 2026-12-01T00:00:00Z running '' '' '' > "$WI/003-b/records.1"; REC 2026-12-01T00:00:00Z running '' '' '' > "$WI/003-b/records.2"
REC 2026-12-01T00:05:00Z pr_open 0 https://x/pr/2 false > "$WI/003-b/records.3"
st 002-a 003-b --watch 0 --since 2026-11-08T00:00:00Z; watch_rc=$?; w="$(cat "$TMP/out")"
watch_ends() { (( watch_rc == 0 )) && [[ $(grep -c '^--- ' <<<"$w") == 3 ]] && grep -q "003-b .*pr_open exit=0 pr=https://x/pr/2" <<<"$w" && grep -q "^CHANGE" <<<"$w"; }
check "R053 AC-4 --watch re-renders until every listed change has a terminal record" watch_ends
refused_ends() { (( refused_rc == 0 && refused_frames == 1 )) && [[ "$same_second" == dispatched ]]; }
check "R053 --watch also ends on a refused record or a fleet:refused tag; a record in the same second as --since (fractional) counts" refused_ends
read_only() { ! grep -Eq "azdo-issue (optin|tag|untag|claim|fields|create|comment)|kubectl.* (create|apply|delete|patch)|-X (POST|PATCH|PUT|DELETE)" "$CALLS"; }
check "R053 AC-4 status makes no write call" read_only
finish
