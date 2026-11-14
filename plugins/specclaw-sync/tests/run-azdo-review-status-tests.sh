#!/usr/bin/env bash
# run-azdo-review-status-tests.sh — specclaw-azdo-pr's clean-loop status (change 064, AC-3).
#
# post_review_status() and its REST helpers are extracted from bin/specclaw-azdo-pr
# and run in a scratch repo whose review round is written by hand. `curl` is a stub:
# a GET of the PR iterations answers with $PR_HEAD, every POST is logged. No network.
#
# Plain bash + git + python3.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REVIEW_BIN="$PLUGIN_DIR/../specclaw-review/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; FAILS=$((FAILS + 1)); cat "$TMP/out"; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t PYTHONDONTWRITEBYTECODE=1

mkdir -p "$TMP/stub"
cat > "$TMP/stub/curl" <<'EOF'
#!/usr/bin/env bash
method=GET body="" wfmt="" url=""
while (($#)); do case "$1" in -X) method="$2"; shift 2 ;; -d) body="$2"; shift 2 ;; -w) wfmt="$2"; shift 2 ;; -H) shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
if [[ "$method" == GET ]]; then
  [[ "$url" == */pullRequests/42/iterations\?* && -n "$PR_HEAD" ]] || exit 22
  printf '{"count":2,"value":[{"id":1,"sourceRefCommit":{"commitId":"0000"}},{"id":2,"sourceRefCommit":{"commitId":"%s"}}]}' "$PR_HEAD"
  exit 0
fi
echo "$method $url $body" >> "$CURL_LOG"
printf '{}'; [[ -n "$wfmt" ]] && printf '\n201'
exit 0
EOF
chmod +x "$TMP/stub/curl"
for fn in adoapi_get adoapi_post post_review_status; do
  sed -n "/^$fn() {/,/^}/p" "$PLUGIN_DIR/bin/specclaw-azdo-pr" >> "$TMP/fn.sh"
done
grep -q '^post_review_status() {' "$TMP/fn.sh" || { echo "FATAL: post_review_status() not found in specclaw-azdo-pr" >&2; exit 2; }

cd "$TMP" && git init -q -b main repo && cd repo || exit 2
echo a > a.txt && git add -A && git commit -qm one
SHA="$(git rev-parse HEAD)"
round() { mkdir -p .specclaw/changes/001-x/review; printf '{"round":1,"final":true,"status":"%s","head":"%s","counts":{}}\n' "$1" "$SHA" > .specclaw/changes/001-x/review/round-1.json; }

post() {
  export CURL_LOG="$TMP/curl.log"; : > "$CURL_LOG"
  ( PATH="$1:/usr/bin:/bin:$(dirname "$(command -v python3)")"; CHANGE_NAME=001-x
    AZDO_ORG=o AZDO_PROJECT=p AZDO_REPO=r AZDO_TOKEN=t
    warn() { echo "WARNING: $*" >&2; }
    # shellcheck disable=SC1091
    source "$TMP/fn.sh"; post_review_status 42 feat/x ) > "$TMP/out" 2>&1
}
posts() { grep -c . "$CURL_LOG"; }

round clean
PR_HEAD="$SHA" post "$TMP/stub:$REVIEW_BIN"; rc=$?
check "AC-3 latest iteration's commit matches: one PR status POST, succeeded, review-loop, iteration 2" \
  '[ "$rc" = 0 ] && [ "$(posts)" = 1 ] && grep -q "pullRequests/42/statuses?api-version=7.1" "$CURL_LOG" && python3 - "$CURL_LOG" <<"PY"
import json, sys
b = json.loads(open(sys.argv[1]).read().split(" ", 2)[2])
assert b["state"] == "succeeded" and b["iterationId"] == 2, b
assert b["context"] == {"genre": "specclaw", "name": "review-loop"}, b
assert b["targetUrl"].endswith("path=/.specclaw/changes/001-x/review/round-1.json&version=GBfeat/x"), b
PY'
for other in 0000000000000000000000000000000000000000 "${SHA:0:10}"; do
  PR_HEAD="$other" post "$TMP/stub:$REVIEW_BIN"; rc=$?
  check "AC-3 iteration commit ${other:0:10}… differs from the final pass: nothing posted, exit 0" '[ "$rc" = 0 ] && [ "$(posts)" = 0 ] && grep -q "not posted" "$TMP/out"'
done
round open
PR_HEAD="$SHA" post "$TMP/stub:$REVIEW_BIN"; rc=$?
check "AC-3 open verdict: nothing posted" '[ "$rc" = 0 ] && [ "$(posts)" = 0 ]'
round clean
PR_HEAD="" post "$TMP/stub:$REVIEW_BIN"; rc=$?
check "AC-3 iterations unreadable: nothing posted, a warning, exit 0" '[ "$rc" = 0 ] && [ "$(posts)" = 0 ] && grep -q WARNING "$TMP/out"'
PR_HEAD="$SHA" post "$TMP/stub"; rc=$?
check "AC-3 specclaw-review not installed: nothing posted, silent, exit 0" '[ "$rc" = 0 ] && [ "$(posts)" = 0 ] && [ ! -s "$TMP/out" ]'

(( FAILS == 0 )) && echo "All azdo review-status tests passed." || echo "$FAILS failed."
exit $(( FAILS > 0 ))
