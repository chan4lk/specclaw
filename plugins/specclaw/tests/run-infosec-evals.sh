#!/usr/bin/env bash
# run-infosec-evals.sh — does the infosec-reviewer agent catch what it should, and stay quiet when it should?
#
# For every case under tests/evals/infosec/ it asks the agent to review the `vulnerable` sample and the `fixed`
# sample, SPECCLAW_INFOSEC_REPS times each, and prints two numbers:
#   catch rate        vulnerable samples whose report has a finding (BLOCK, WARN or NOTE heading) citing the
#                     expected rule id or keyword
#   false-alarm rate  fixed samples whose report has any BLOCK finding
# A call that returns nothing is left out of both rates and listed as "no answer". Any such call makes the rates
# UNKNOWN and the run exit 1: a call that never ran must not read as clear.
#
# THIS SUITE COSTS API CALLS, so it is opt-in (SPECCLAW_INFOSEC_EVALS=1) and runs nightly, never on every push.
# The cheap structural half is run-infosec-eval-cases-tests.sh.
#
# Environment:
#   SPECCLAW_INFOSEC_EVALS=1         required, otherwise this skips and exits 0
#   SPECCLAW_INFOSEC_REPS=3          reps per sample (a positive integer)
#   SPECCLAW_INFOSEC_MODEL=<id>      a full model ID (default claude-sonnet-5-5), recorded in the result with the CLI version
#   SPECCLAW_INFOSEC_CASE=<name>     run one case only
#   SPECCLAW_INFOSEC_TIMEOUT=300     seconds before one call is given up (counts as no answer)
#   SPECCLAW_INFOSEC_RESULTS_DIR=<d> where the result file goes (default tests/results)
#   SPECCLAW_INFOSEC_RULES_FOR=<f>   print the rule files a sample named <f> is reviewed with, and exit (no model call)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
CASES="$SCRIPT_DIR/evals/infosec"
AGENT="$PLUGIN_DIR/agents/infosec-reviewer.md"
RESULTS_DIR="${SPECCLAW_INFOSEC_RESULTS_DIR:-$SCRIPT_DIR/results}"
REPS="${SPECCLAW_INFOSEC_REPS:-3}"
MODEL="${SPECCLAW_INFOSEC_MODEL:-claude-sonnet-5-5}"
ONLY="${SPECCLAW_INFOSEC_CASE:-}"
TIMEOUT="${SPECCLAW_INFOSEC_TIMEOUT:-300}"

# rules_for <sample> -> the preset and pack files for its stack, one per line; base is always included.
rules_for() {
  local stack
  case "${1##*.}" in
    cs) stack=dotnet ;;
    py) stack=python ;;
    js|ts) stack=node ;;
    *) stack= ;;
  esac
  echo "$PLUGIN_DIR/presets/base.md"
  [ -z "$stack" ] || echo "$PLUGIN_DIR/presets/$stack.md"
  echo "$REPO_ROOT/plugins/specclaw-review/review-rules/base.md"
  [ -z "$stack" ] || echo "$REPO_ROOT/plugins/specclaw-review/review-rules/$stack.md"
}

if [ -n "${SPECCLAW_INFOSEC_RULES_FOR:-}" ]; then rules_for "$SPECCLAW_INFOSEC_RULES_FOR"; exit 0; fi

if [ "${SPECCLAW_INFOSEC_EVALS:-}" != "1" ]; then
  echo "run-infosec-evals.sh: SKIPPED. It drives a real model and costs API calls." >&2
  echo "Run it with: SPECCLAW_INFOSEC_EVALS=1 bash plugins/specclaw/tests/run-infosec-evals.sh" >&2
  exit 0
fi

[[ "$REPS" =~ ^[1-9][0-9]*$ ]] || { echo "FATAL: SPECCLAW_INFOSEC_REPS must be a positive integer, got '$REPS'." >&2; exit 2; }

# A missing CLI is a failure, not a skip: a green eval that measured nothing is the failure this suite guards against.
command -v claude >/dev/null 2>&1 || { echo "FATAL: the \`claude\` CLI is not on PATH, cannot measure." >&2; exit 2; }

# The agent's instructions without its front matter (each sample's rules come from rules_for).
INSTRUCTIONS="$(awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {f=0; next} !f' "$AGENT")"
# Finding headings are read by the gate itself (`--headings`), so the false-alarm rate measures exactly
# what blocks a PR: one definition, no copy here to drift.
GATE="${SPECCLAW_INFOSEC_GATE:-$PLUGIN_DIR/bin/specclaw-security-gate}"  # override: tests only
REPORT_TMP="$(mktemp)"
trap 'rm -f "$REPORT_TMP"' EXIT
# read_report <report-text>: fails unless the gate reads one valid verdict from it (a refusal, an error printed
# on stdout or cut-off prose is no answer, never "no finding"); otherwise prints `<SEVERITY>\t<heading>` lines.
read_report() {
  printf '%s\n' "$1" > "$REPORT_TMP"
  "$GATE" --verdict "$REPORT_TMP" >/dev/null && "$GATE" --headings "$REPORT_TMP"
}

# review <sample-file> -> the report text; empty when the call failed or exited non-zero (a text error is not a report)
review() {
  local sample="$1" ext path
  ext="${sample##*.}"
  # A neutral path, so the file name never says "vulnerable" or "fixed".
  if [ "$ext" = md ]; then path=".specclaw/changes/eval/reports/T3.md"; else path="src/handler.$ext"; fi
  # The preset and review-pack files for this sample's stack, whole. A real run passes only their security
  # rules, so the measured prompt is larger than the shipped one (a known difference, kept for simplicity).
  local rules out
  mapfile -t rules < <(rules_for "$sample")
  out="$(timeout "$TIMEOUT" claude -p "$INSTRUCTIONS

Mode: verify
Change: eval
Do not write any file. Print the full report you would write to security-report.md, and nothing else.

## Changed files
### $path
$(cat "$sample")

## Spec
(none)

## Security rules
$(cat "${rules[@]}")" --model "$MODEL" --max-turns 1 2>/dev/null)" || return 0
  printf '%s' "$out"
}

mkdir -p "$RESULTS_DIR"
OUT="$RESULTS_DIR/infosec-$(date +%Y%m%d-%H%M%S).md"
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
CLI="$(claude --version 2>/dev/null | head -1)"
printf '# infosec-reviewer evals\n\n**Model:** %s  **CLI:** %s  **Reps:** %s  **Commit:** %s\n\n| Case | Caught | False alarms | No answer |\n|---|---|---|---|\n' \
  "$MODEL" "${CLI:-unknown}" "$REPS" "$COMMIT" > "$OUT"

caught=0; v_answered=0; alarms=0; f_answered=0; no_answer=0
for d in "$CASES"/*/; do
  c="$(basename "$d")"
  [ -z "$ONLY" ] || [ "$ONLY" = "$c" ] || continue
  want="$(sed -n 's/^rule: *//p' "$d/expect" | head -1 | tr -d ' ')"
  [ -n "$want" ] || { echo "FATAL: case $c has no 'rule:' line in expect." >&2; exit 2; }
  c_hit=0; c_alarm=0; c_none=0
  for _ in $(seq 1 "$REPS"); do
    # A report the gate could not read (gate missing, crashed) is no answer, never "no finding".
    r="$(review "$(ls "$d"/vulnerable.* | head -1)")"
    if [ -z "$r" ] || ! h="$(read_report "$r")"; then
      c_none=$((c_none + 1))
    else
      v_answered=$((v_answered + 1))
      # Only a finding heading counts: the keyword also appears in quoted code and in prose that approves it.
      if grep -qE "\b($want)\b" <<<"$h"; then c_hit=$((c_hit + 1)); fi
    fi
    r="$(review "$(ls "$d"/fixed.* | head -1)")"
    if [ -z "$r" ] || ! h="$(read_report "$r")"; then
      c_none=$((c_none + 1))
    else
      f_answered=$((f_answered + 1))
      if grep -q '^BLOCK' <<<"$h"; then c_alarm=$((c_alarm + 1)); fi
    fi
  done
  caught=$((caught + c_hit)); alarms=$((alarms + c_alarm)); no_answer=$((no_answer + c_none))
  printf '| %s | %s | %s | %s |\n' "$c" "$c_hit" "$c_alarm" "$c_none" >> "$OUT"
  printf '%-24s caught %s  false alarms %s  no answer %s  (of %s reps)\n' "$c" "$c_hit" "$c_alarm" "$c_none" "$REPS"
done

[ $((v_answered + f_answered + no_answer)) -gt 0 ] || { echo "FATAL: no case ran." >&2; exit 2; }
status=0
if [ "$no_answer" -gt 0 ] || [ "$v_answered" -eq 0 ] || [ "$f_answered" -eq 0 ]; then status=1; fi
{
  if [ "$status" -ne 0 ]; then
    printf '\n**Catch rate:** UNKNOWN (%s call(s) gave no answer)\n' "$no_answer"
    printf '**False-alarm rate:** UNKNOWN (%s call(s) gave no answer)\n' "$no_answer"
  else
    printf '\n**Catch rate:** %s%% (%s/%s)\n' $((caught * 100 / v_answered)) "$caught" "$v_answered"
    printf '**False-alarm rate:** %s%% (%s/%s)\n' $((alarms * 100 / f_answered)) "$alarms" "$f_answered"
  fi
  printf '**Model:** %s\n' "$MODEL"
} | tee -a "$OUT"
echo "Result: $OUT"
exit "$status"
