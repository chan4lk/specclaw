#!/usr/bin/env bash
# run-review-status-tests.sh — specclaw-pr's clean-loop status (change 064, AC-2).
#
# post_review_status() is extracted from bin/specclaw-pr and run in a scratch repo
# whose review round is written by hand. `gh` is a stub that answers `pr view` with
# $PR_HEAD and logs every `api` call: no network. The real specclaw-review decides.
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

mkdir -p "$TMP/stub" "$TMP/nogh"
cat > "$TMP/stub/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") [ -n "$PR_HEAD" ] || exit 1; echo "$PR_HEAD feat/x" ;;
  "api "*) echo "$*" >> "$GH_LOG" ;;
esac
EOF
chmod +x "$TMP/stub/gh"
sed -n '/^post_review_status() {/,/^}/p' "$PLUGIN_DIR/bin/specclaw-pr" > "$TMP/fn.sh"
grep -q '^post_review_status() {' "$TMP/fn.sh" || { echo "FATAL: post_review_status() not found in specclaw-pr" >&2; exit 2; }

cd "$TMP" && git init -q -b main repo && cd repo || exit 2
echo a > a.txt && git add -A && git commit -qm one
SHA="$(git rev-parse HEAD)"
mkdir -p .specclaw/changes/001-x/review
round() { mkdir -p .specclaw/changes/001-x/review; printf '{"round":1,"final":true,"status":"%s","head":"%s","counts":{}}\n' "$1" "$SHA" > .specclaw/changes/001-x/review/round-1.json; }

# post <PATH prefix> — run the extracted function; stdout+stderr to $TMP/out, gh api calls to $GH_LOG
post() {
  export GH_LOG="$TMP/gh.log"; : > "$GH_LOG"
  ( PATH="$1:/usr/bin:/bin:$(dirname "$(command -v python3)")"; CHANGE_NAME=001-x
    warn() { echo "WARNING: $*" >&2; }
    # shellcheck disable=SC1091
    source "$TMP/fn.sh"; post_review_status "https://github.com/o/r/pull/7" ) > "$TMP/out" 2>&1
}
posts() { grep -c . "$GH_LOG"; }

round clean
PR_HEAD="$SHA" post "$TMP/stub:$REVIEW_BIN"; rc=$?
check "AC-2 head matches: exactly one status POST on that SHA, success, specclaw/review-loop" \
  '[ "$rc" = 0 ] && [ "$(posts)" = 1 ] && grep -q "statuses/$SHA " "$GH_LOG" && grep -q "state=success" "$GH_LOG" && grep -q "context=specclaw/review-loop" "$GH_LOG" && grep -q "target_url=https://github.com/o/r/blob/feat/x/.specclaw/changes/001-x/review/round-1.json" "$GH_LOG"'
for other in 0000000000000000000000000000000000000000 "${SHA:0:10}"; do
  PR_HEAD="$other" post "$TMP/stub:$REVIEW_BIN"; rc=$?
  check "AC-2 PR head ${other:0:10}… differs from the final pass: nothing posted, exit 0" '[ "$rc" = 0 ] && [ "$(posts)" = 0 ] && grep -q "not posted" "$TMP/out"'
done
git add .specclaw && git commit -qm records-only
REC="$(git rev-parse HEAD)"
PR_HEAD="$REC" post "$TMP/stub:$REVIEW_BIN"; rc=$?
check "AC-2 .specclaw-only commits after the final pass: one status POST on the PR head" '[ "$rc" = 0 ] && [ "$(posts)" = 1 ] && grep -q "statuses/$REC " "$GH_LOG"'
echo c > c.txt && echo r > .specclaw/r.md && git add -A && git commit -qm mixed
PR_HEAD="$(git rev-parse HEAD)" post "$TMP/stub:$REVIEW_BIN"; rc=$?
check "AC-2 a commit touching one code file and one .specclaw file: nothing posted" '[ "$rc" = 0 ] && [ "$(posts)" = 0 ] && grep -q "not posted" "$TMP/out"'
git reset -q --hard "$SHA"
round open
PR_HEAD="$SHA" post "$TMP/stub:$REVIEW_BIN"; rc=$?
check "AC-2 open verdict at the PR head: nothing posted" '[ "$rc" = 0 ] && [ "$(posts)" = 0 ]'
round clean
PR_HEAD="" post "$TMP/stub:$REVIEW_BIN"; rc=$?
check "AC-2 PR head unreadable: nothing posted, a warning, exit 0" '[ "$rc" = 0 ] && [ "$(posts)" = 0 ] && grep -q WARNING "$TMP/out"'
PR_HEAD="$SHA" post "$TMP/stub"; rc=$?
check "AC-2 specclaw-review not installed: nothing posted, silent, exit 0" '[ "$rc" = 0 ] && [ "$(posts)" = 0 ] && [ ! -s "$TMP/out" ]'

(( FAILS == 0 )) && echo "All review-status tests passed." || echo "$FAILS failed."
exit $(( FAILS > 0 ))
