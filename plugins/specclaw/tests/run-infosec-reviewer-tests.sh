#!/usr/bin/env bash
# run-infosec-reviewer-tests.sh — change 069: the infosec-reviewer agent, its config key and its verify step.
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
  "**Auth flows:**" "**Secrets in records:**" "**Prompt injection:**" "**Credentials:**" "**Shell-outs:**" "**Supply chain:**")

missing() { local f="$1" i out=""; for i in "${ITEMS[@]}"; do grep -qF -- "$i" "$f" || out="$out|$i"; done; echo "$out"; }

check "AC-1 agent has front matter and every step and check" '[ -f "$AGENT" ] && head -1 "$AGENT" | grep -q "^---$" && grep -q "^name: infosec-reviewer$" "$AGENT" && grep -q "^description: ." "$AGENT" && grep -q "^tools: \[" "$AGENT" && grep -q "^model: ." "$AGENT" && [ -z "$(missing "$AGENT")" ]'
check "AC-2 workflow.security_review ships false" 'grep -qE "^  security_review: false( |$)" "$PLUGIN_DIR/templates/config.yaml"'
step="$(sed -n '/^## Step 3.52/,/^## Step 3.55/p' "$PLUGIN_DIR/references/full/verify.md")"
check "AC-3 verify step skips when the flag is off, is advisory, and reports a failed run as NOT RUN" 'grep -q "infosec-reviewer" <<<"$step" && grep -qF "If \`false\` or not set, skip" <<<"$step" && grep -qi "advisory" <<<"$step" && grep -q "NOT RUN" <<<"$step"'
check "AC-3b the agent never copies a secret into the report" 'grep -q "Never copy a secret into the report" "$AGENT" && grep -qF "[REDACTED]" "$AGENT"'
for i in "${ITEMS[@]}"; do
  grep -vF -- "$i" "$AGENT" > "$TMP/mutant.md"
  check "AC-4 agent without $i is reported by name" '[ "$(missing "$TMP/mutant.md")" = "|$i" ]'
done
check "AC-5 CI registers this suite" 'grep -q "run-infosec-reviewer-tests.sh" "$PLUGIN_DIR/../../.github/workflows/ci.yml"'

echo
[ "$FAILS" -eq 0 ] && echo "All infosec-reviewer tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
