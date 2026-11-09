# shellcheck shell=bash disable=SC2034
export SPECCLAW_DIR="$TMP/repo/.specclaw" FLEET_AZDO_ISSUE="$TMP/stub/specclaw-azdo-issue" AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t WI="$TMP/wi" TMP
stub specclaw-azdo-issue '[[ "$1" == records ]] || exit 0; [[ -f "$WI/$3.fail" ]] && exit 1; cat "$WI/$3" 2>/dev/null || echo "{\"records\":[]}"'
stub curl 'f="$TMP/api/$(grep -oE "(pullrequests|builds)/[0-9]+" <<<"$*" | tr / -)"; [[ -f "$f" ]] || { printf "\n404"; exit 0; }
[[ "$(cat "$f")" == FAIL500 ]] && { printf "\n500"; exit 0; }; cat "$f"; printf "\n200"'
stub kubectl '[[ -n "${KUBE_FAIL:-}" ]] && exit 1
case "${KUBE_JUNK:-}:$*" in empty:*) exit 0 ;; html:*) echo "<html>"; exit 0 ;; items:*"get jobs"*) echo "{\"items\":\"x\"}"; exit 0 ;; itemjunk:*"get jobs"*) echo "{\"items\":[1]}"; exit 0 ;; esac
st="{\"active\":1}"; case "${KUBE_PHASE:-}" in failed) st="{\"failed\":1}" ;; complete) st="{\"succeeded\":1}" ;; gone) [[ "$*" == *"get jobs"* ]] && { echo "{\"items\":[]}"; exit 0; } ;; esac
case "$*" in *"get jobs"*) echo "{\"items\":[{\"metadata\":{\"name\":\"fleet-003-b\",\"creationTimestamp\":\"2026-11-09T12:05:00Z\"},\"status\":$st}]}" ;; *"get pods"*) printf Running ;; esac'
mk() { local d="$SPECCLAW_DIR/changes/$1"; mkdir -p "$d"; echo '{"phases":{"proposal":{"status":"approved"}}}' > "$d/state.json"
  printf '**Feature:** cat\n**Depends on:** %s\n' "$2" > "$d/proposal.md"; printf '**Azure Boards Work Item:** [#%s](https://x)\n' "$3" > "$d/status.md"; }
api() { mkdir -p "$TMP/api"; printf '%s' "$2" > "$TMP/api/$1"; }
reset() {
  rm -rf "$TMP/repo" "$TMP/api" "$WI"; mkdir -p "$WI"; mk 002-a none 11; mk 003-b 002-a 12; mk 004-c none 13
  cat > "$WI/002-a" <<'J'
{"records":[{"at":"2026-11-09T12:00:00.123Z","state":"pr_open","pr":"https://x/pullrequest/11","agent_started":"2026-11-09T11:10:00Z","agent_ended":"2026-11-09T11:40:00Z","agent_s":"1800","cost_usd":"2.5","turns":"40","model":"</script><!--<script><b>x","review_rounds":"3","agent_commits":"7"},
{"at":"2026-11-09T11:09:00Z","state":"running","claude_fetch_s":"5"},{"at":"2026-11-09T11:05:00Z","state":"dispatched","pipeline_run":"100","job":"fleet-002-a"},
{"at":"2026-11-08T10:00:00Z","state":"failed","exit":"1","review_rounds":"99"},{"at":"2026-11-08T09:00:00Z","state":"dispatched","pipeline_run":"90"}]}
J
  echo '{"records":[{"at":"2026-11-09T12:10:00Z","state":"running","claude_fetch_s":"7"},{"at":"2026-11-09T12:05:00Z","state":"dispatched","pipeline_run":"101","job":"fleet-003-b"}]}' > "$WI/003-b"
  api pullrequests-11 '{"status":"completed","creationDate":"2026-11-09T11:40:00.5Z","closedDate":"2026-11-09T12:00:00Z"}'
  api builds-100 '{"queueTime":"2026-11-09T11:04:00.5Z","startTime":"2026-11-09T11:04:30Z","finishTime":"2026-11-09T11:06:30Z"}'; api builds-101 FAIL500
}
run() { (cd "$TMP/repo" && "$FLEET" report "$@") 2> "$TMP/err"; }
