#!/usr/bin/env bash
# run-infosec-eval-cases-tests.sh — change 069: the infosec eval cases are well formed.
# Cheap, no model calls. The scoring run is run-infosec-evals.sh (opt-in).
# shellcheck disable=SC2016  # check() evals its single-quoted condition later
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
CASES="$PLUGIN_DIR/tests/evals/infosec"
RULES="$ROOT/plugins/specclaw-review/review-rules"
FAILS=0
ok() { echo "PASS: $1"; }
ko() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# problems <cases-dir>: one "<case>: <what is wrong>" line per defect.
problems() {
  local d c rule kw
  for d in "$1"/*/; do
    c="$(basename "$d")"
    compgen -G "$d/vulnerable.*" >/dev/null || echo "$c: no vulnerable sample"
    compgen -G "$d/fixed.*" >/dev/null || echo "$c: no fixed sample"
    if [ ! -s "$d/expect" ]; then echo "$c: no expect"; continue; fi
    grep -qE '^rule: [A-Za-z0-9]+(\|[A-Za-z0-9]+)?$' "$d/expect" || { echo "$c: expect is not exactly 'rule: <ID>|<Keyword>'"; continue; }
    rule="$(sed -n 's/^rule: *\([A-Za-z0-9]*\).*/\1/p' "$d/expect" | head -1)"
    [ -n "$rule" ] || { echo "$c: expect has no 'rule:' line"; continue; }
    grep -qE "^- \*\*$rule[ .*]" "$RULES"/*.md || echo "$c: rule $rule is in no review pack"
    kw="$(sed -n 's/^rule: *[A-Za-z0-9]*|\([A-Za-z0-9]*\).*/\1/p' "$d/expect" | head -1)"
    [ -z "$kw" ] || grep -qF -- "- **$kw:**" "$PLUGIN_DIR"/presets/*.md || echo "$c: keyword $kw is in no preset"
  done
}

check "AC-10 at least 8 cases" '[ "$(ls -d "$CASES"/*/ | wc -l)" -ge 8 ]'
check "AC-10 every case is well formed" '[ -z "$(problems "$CASES")" ]'

for kind in fixed expect bogus badkw badformat; do
  rm -rf "$TMP/m"; cp -r "$CASES" "$TMP/m"; c="$(ls "$TMP/m" | head -1)"
  case "$kind" in
    fixed) rm "$TMP/m/$c"/fixed.* ; want="$c: no fixed sample" ;;
    expect) rm "$TMP/m/$c/expect" ; want="$c: no expect" ;;
    bogus) echo "rule: B999" > "$TMP/m/$c/expect" ; want="$c: rule B999 is in no review pack" ;;
    badkw) echo "rule: B16|Nope" > "$TMP/m/$c/expect" ; want="$c: keyword Nope is in no preset" ;;
    badformat) echo "rule: B16 | Codes;" > "$TMP/m/$c/expect" ; want="$c: expect is not exactly 'rule: <ID>|<Keyword>'" ;;
  esac
  check "AC-11 case with $kind broken is reported by name" '[ "$(problems "$TMP/m")" = "$want" ]'
done

RUNNER="$PLUGIN_DIR/tests/run-infosec-evals.sh"
check "AC-12 runner skips with exit 0 unless the opt-in is set" 'out="$(env -u SPECCLAW_INFOSEC_EVALS bash "$RUNNER" 2>&1)"; rc=$?; [ "$rc" -eq 0 ] && grep -q SKIPPED <<<"$out"'
# A stub `claude` that flags the dev-bypass sample and passes the fixed one, so the scoring is tested without a model.
mkdir -p "$TMP/bin"
printf '%s\n' '#!/usr/bin/env bash' '[ "${STUB_FAIL:-}" = 1 ] && exit 0' '[ "${STUB_EXIT1:-}" = 1 ] && { echo "Error: max turns reached"; exit 1; }' '[ "${STUB_PROSE:-}" = 1 ] && { echo "No findings. The codes and DevFlags code looks fine."; exit 0; }' 'if [ "${STUB_ALWAYS_BLOCK:-}" = 1 ] || grep -q "x-dev-user" <<<"$*"; then echo "### [BLOCK] src/handler.js:2 - B16 DevFlags"; else echo "No findings."; fi' > "$TMP/bin/claude"
chmod +x "$TMP/bin/claude"
results_before="$(ls -A "$PLUGIN_DIR"/tests/results 2>/dev/null)"
run_stub() { PATH="$TMP/bin:$PATH" SPECCLAW_INFOSEC_EVALS=1 SPECCLAW_INFOSEC_REPS="${REPS:-1}" SPECCLAW_INFOSEC_CASE=dev-bypass SPECCLAW_INFOSEC_RESULTS_DIR="$TMP/results" bash "$RUNNER" 2>&1; }
check "AC-12 runner prints catch rate, false-alarm rate and model" 'out="$(run_stub)"; grep -q "Catch rate:\*\* 100%" <<<"$out" && grep -q "False-alarm rate:\*\* 0%" <<<"$out" && grep -q "Model:\*\* " <<<"$out"'
check "AC-12 a fixed sample that draws a BLOCK counts as a false alarm" 'out="$(STUB_ALWAYS_BLOCK=1 run_stub)"; grep -q "False-alarm rate:\*\* 100%" <<<"$out"'
check "AC-12 calls that give no answer make the rates UNKNOWN and the run fail" 'out="$(STUB_FAIL=1 run_stub)"; rc=$?; [ "$rc" -ne 0 ] && grep -q "Catch rate:\*\* UNKNOWN" <<<"$out" && ! grep -q "False-alarm rate:\*\* 0%" <<<"$out"'
check "AC-12 a failed call that still prints text is no answer, not a report" 'out="$(STUB_EXIT1=1 run_stub)"; rc=$?; [ "$rc" -ne 0 ] && grep -q "Catch rate:\*\* UNKNOWN" <<<"$out"'
check "AC-12 a non-integer reps value is refused" 'out="$(REPS=abc run_stub)"; grep -q "must be a positive integer" <<<"$out"'
check "AC-12 a keyword in prose or code, not in a finding, is not a catch" 'out="$(PATH="$TMP/bin:$PATH" STUB_PROSE=1 SPECCLAW_INFOSEC_EVALS=1 SPECCLAW_INFOSEC_REPS=1 SPECCLAW_INFOSEC_CASE=dev-bypass SPECCLAW_INFOSEC_RESULTS_DIR="$TMP/results" bash "$RUNNER" 2>&1)"; grep -q "Catch rate:\*\* 0%" <<<"$out"'
check "AC-12 the runner leaves tests/results alone when told to write elsewhere" '[ "$(ls -A "$PLUGIN_DIR"/tests/results 2>/dev/null)" = "$results_before" ] && ls "$TMP/results"/infosec-*.md >/dev/null'
check "AC-13 nightly workflow exists" 'grep -q "cron:" "$ROOT/.github/workflows/infosec-evals.yml" && grep -q "run-infosec-evals.sh" "$ROOT/.github/workflows/infosec-evals.yml"'
check "AC-13 CI registers this suite" 'grep -q "run-infosec-eval-cases-tests.sh" "$ROOT/.github/workflows/ci.yml"'

echo
[ "$FAILS" -eq 0 ] && echo "All infosec eval case tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
