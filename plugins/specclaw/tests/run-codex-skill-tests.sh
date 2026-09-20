#!/usr/bin/env bash
# run-codex-skill-tests.sh — ensure the Codex entry point stays a thin adapter.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
SKILL_DIR="$REPO_ROOT/.agents/skills/specclaw"
SKILL_FILE="$SKILL_DIR/SKILL.md"
WORKFLOW_FILE="$REPO_ROOT/.github/workflows/ci.yml"

failed=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

[ -f "$SKILL_FILE" ] || fail "Codex adapter exists at .agents/skills/specclaw/SKILL.md"

if [ -f "$SKILL_FILE" ]; then
  grep -qx 'name: specclaw' "$SKILL_FILE" \
    && pass "adapter has the specclaw skill name" \
    || fail "adapter declares name: specclaw"

  awk '
    /^description:[[:space:]]*[^[:space:]].*/ { found=1 }
    /^---$/ && seen++ > 0 { exit }
    END { exit(found ? 0 : 1) }
  ' "$SKILL_FILE" \
    && pass "adapter has a non-empty description" \
    || fail "adapter has a non-empty description"

  grep -Fq 'plugins/specclaw/skills' "$SKILL_FILE" \
    && pass "adapter delegates to canonical skills" \
    || fail "adapter delegates to canonical skills"

  grep -Fq 'plugins/specclaw/bin' "$SKILL_FILE" \
    && pass "adapter resolves canonical helper binaries" \
    || fail "adapter resolves canonical helper binaries"

  grep -Fq 'CLAUDE_PLUGIN_ROOT' "$SKILL_FILE" \
    && pass "adapter documents canonical resource-root compatibility" \
    || fail "adapter documents canonical resource-root compatibility"

  grep -Fq 'git rev-parse --show-toplevel' "$SKILL_FILE" \
    && pass "adapter resolves the checkout root at runtime" \
    || fail "adapter resolves the checkout root at runtime"

  grep -Fq 'SPECCLAW_PLUGIN_ROOT="$REPO_ROOT/plugins/specclaw"' "$SKILL_FILE" \
    && pass "adapter derives the canonical plugin root" \
    || fail "adapter derives the canonical plugin root"

  grep -Fq '$SPECCLAW_PLUGIN_ROOT/skills/<verb>/SKILL.md' "$SKILL_FILE" \
    && pass "adapter routes verbs through canonical skill directories" \
    || fail "adapter routes verbs through canonical skill directories"
fi

for verb_dir in "$PLUGIN_DIR"/skills/*; do
  [ -f "$verb_dir/SKILL.md" ] || continue
  verb="$(basename "$verb_dir")"
  [ -f "$PLUGIN_DIR/skills/$verb/SKILL.md" ] \
    && pass "canonical skill target exists: $verb" \
    || fail "canonical skill target exists: $verb"
done

for duplicate in skills bin templates references; do
  [ ! -e "$SKILL_DIR/$duplicate" ] \
    && pass "adapter does not duplicate $duplicate" \
    || fail "adapter does not duplicate $duplicate"
done

[ -f "$WORKFLOW_FILE" ] || fail "CI workflow exists"
if [ -f "$WORKFLOW_FILE" ]; then
  grep -Fq 'run: bash plugins/specclaw/tests/run-codex-skill-tests.sh' "$WORKFLOW_FILE" \
    && pass "CI runs the Codex adapter validation" \
    || fail "CI runs the Codex adapter validation"
fi

adapter_files="$(find "$SKILL_DIR" -type f -print | sed "s|$SKILL_DIR/||" | sort)"
[ "$adapter_files" = 'SKILL.md' ] \
  && pass "adapter contains only its entry-point file" \
  || fail "adapter contains only its entry-point file"

[ "$failed" -eq 0 ] || exit 1
printf 'All Codex skill adapter checks passed.\n'
