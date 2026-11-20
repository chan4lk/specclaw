#!/usr/bin/env bash
# run-infosec-reviewer-tests.sh — change 070: the infosec-reviewer agent, its config key and its verify step.
# shellcheck disable=SC2016  # check() evals its single-quoted condition later
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="$PLUGIN_DIR/agents/infosec-reviewer.md"
FAILS=0
ok() { echo "PASS: $1"; }
ko() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ITEMS=("**Model the threat.**" "**Think like an attacker.**" "**Check the stack rules.**" "**Check the specclaw-specific surface.**"
  "**Auth flows:**" "**Secrets in records:**" "**Prompt injection:**" "**Credentials:**" "**Shell-outs:**" "**Supply chain:**"
  "**Mode plan:**" "**Mode build:**" "**Mode verify:**"
  "The rule field of every finding heading starts with the pack rule id or preset keyword it breaks (for example B13 or Access), so a waiver can name it.")

missing() { local f="$1" i out=""; for i in "${ITEMS[@]}"; do grep -qF -- "$i" "$f" || out="$out|$i"; done; echo "$out"; }

check "AC-1 agent has front matter and every step and check" '[ -f "$AGENT" ] && head -1 "$AGENT" | grep -q "^---$" && grep -q "^name: infosec-reviewer$" "$AGENT" && grep -q "^description: ." "$AGENT" && grep -q "^tools: \[" "$AGENT" && grep -q "^model: ." "$AGENT" && [ -z "$(missing "$AGENT")" ]'
check "AC-2 workflow.security_review ships true" 'grep -qE "^  security_review: true( |$)" "$PLUGIN_DIR/templates/config.yaml"'
check "AC-2b workflow.security_review_block ships false" 'grep -qE "^  security_review_block: false( |$)" "$PLUGIN_DIR/templates/config.yaml"'
step="$(sed -n '/^## Step 3.52/,/^## Step 3.55/p' "$PLUGIN_DIR/references/full/verify.md")"
check "AC-3 verify step skips only when the flag is explicitly off, is advisory, and reports a failed run as NOT RUN" 'grep -q "infosec-reviewer" <<<"$step" && grep -qF "If it is explicitly \`false\`, skip" <<<"$step" && grep -q "missing key means on" <<<"$step" && grep -qi "advisory" <<<"$step" && grep -q "NOT RUN" <<<"$step"'
check "AC-3b the agent never copies a secret into the report" 'grep -q "Never copy a secret into the report" "$AGENT" && grep -qF "[REDACTED]" "$AGENT"'
for i in "${ITEMS[@]}"; do
  grep -vF -- "$i" "$AGENT" > "$TMP/mutant.md"
  check "AC-4 agent without $i is reported by name" '[ "$(missing "$TMP/mutant.md")" = "|$i" ]'
done
agent_out="$(sed -n '/^# Output/,$p' "$AGENT")"
check "AC-6 agent output section names what each mode writes" 'grep -q "security-requirements.md" <<<"$agent_out" && grep -q "security/<T>.md" <<<"$agent_out" && grep -q "security-report.md" <<<"$agent_out" && grep -qF "**SR-1**" <<<"$agent_out"'
plan_step="$(sed -n '/^3c\./,/^4\. /p' "$PLUGIN_DIR/references/full/plan.md")"
check "AC-7 plan spawns the agent in plan mode unless the flag is false, and turns SR-n into criteria" 'grep -q "infosec-reviewer" <<<"$plan_step" && grep -q "plan\*\* mode" <<<"$plan_step" && grep -qF "If it is explicitly \`false\` (a missing key means on)" <<<"$plan_step" && grep -q "acceptance criterion" <<<"$plan_step" && grep -q "SR-n" <<<"$plan_step"'
build_step="$(sed -n '/2c\. \*\*Per-task security review/,/3\. Close the span/p' "$PLUGIN_DIR/references/full/build.md")"
payload_step="$(sed -n '/Build the agent context payload/,/Pick the agent and its budget/p' "$PLUGIN_DIR/references/full/build.md")"
check "AC-8 build reviews entry-point tasks unless the flag is false, advisory, and hands builders the requirements" 'grep -q "infosec-reviewer" <<<"$build_step" && grep -qF "unless \`workflow.security_review\` is \`false\`" <<<"$build_step" && grep -q "entry point" <<<"$build_step" && grep -q "build\*\* mode" <<<"$build_step" && grep -qi "advisory" <<<"$build_step" && grep -q "NOT_RUN" <<<"$build_step" && grep -q "security-requirements.md" <<<"$payload_step"'
check "AC-9 verify passes the requirements and counts unmet ones" 'grep -q "security-requirements.md" <<<"$step" && grep -q "security/" <<<"$step" && grep -q "unmet" <<<"$step"'
check "072 AC-5 verify Step 3.52 runs specclaw-security-gate and records its line" 'grep -q "specclaw-security-gate" <<<"$step" && grep -qF "**Security gate:**" <<<"$step"'
check "AC-5 CI registers this suite" 'grep -q "run-infosec-reviewer-tests.sh" "$PLUGIN_DIR/../../.github/workflows/ci.yml"'

echo
[ "$FAILS" -eq 0 ] && echo "All infosec-reviewer tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
