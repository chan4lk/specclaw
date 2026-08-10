#!/usr/bin/env bash
# run-loop-gate-tests.sh — regression suite for the two report readers behind
# `specclaw-loop gates`: the review gate's BLOCK counter and extract_verdict.
#
# The defects, both reproduced against the shipped report formats:
#
#   D1: the review gate counted BLOCK with `grep -oE '\bBLOCK\b' | wc -l` over the
#       whole file. agents/code-reviewer.md prints the word twice in every clean
#       report — once in "N findings: 0 BLOCK, 2 WARN, 2 NOTE" and again in the
#       verdict rationale — so an APPROVED_WITH_NOTES report scored 2 blockers.
#       With workflow.code_review: true the review gate could never be green, so
#       the loop burned every iteration on a change that was already done and then
#       halted on the cap.
#
#   D2: extract_verdict took the first case-insensitive PASS|FAIL|PARTIAL token
#       anywhere in the file. Verification prose says "the lint gate did not fail"
#       and "all criteria pass", so whichever phrase a model happened to write
#       above the `**Verdict:**` line decided the verify gate.
#
# Plain bash + coreutils only (no jq). Run from anywhere:
#   bash plugins/specclaw/tests/run-loop-gate-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
LOOP="$BIN_DIR/specclaw-loop"

if [[ ! -x "$LOOP" ]]; then
  echo "FATAL: missing or non-executable: $LOOP" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (= '$actual')"
  else
    fail "$label — expected '$expected', got '$actual'"
  fi
}

CHANGE="gate-fixture"

# ── Fixture builders ──────────────────────────────────────────────────────────

# A .specclaw tree whose tasks + tests + verify gates are all green, so any red
# gate in a case below is attributable to the report under test.
# $1 = destination dir, $2 = workflow.code_review value (true|false)
make_specclaw() {
  local dir="$1" code_review="$2"
  mkdir -p "$dir/changes/$CHANGE"
  cat > "$dir/config.yaml" <<EOF
version: 1

build:
  test_command: ""
  lint_command: ""
  build_command: ""

workflow:
  code_review: ${code_review}
EOF
  cat > "$dir/changes/$CHANGE/tasks.md" <<'EOF'
# Tasks: gate fixture

## Tasks

### Wave 1 — only wave

- [x] `T1` — a task that is done
  - Files: none
  - Estimate: small
EOF
  write_verify "$dir" PASS
}

# $1 = specclaw dir, $2 = verdict token
write_verify() {
  cat > "$1/changes/$CHANGE/verify-report.md" <<EOF
# Verification Report: ${CHANGE}

**Verified:** 2026-08-10
**Model:** test
**Verdict:** $2

## Summary

**Passed:** 1/1 criteria
EOF
}

# ── Gate JSON accessors (grep/sed — the suites stay jq-free) ───────────────────

gate_obj() { printf '%s' "$1" | grep -oE "\{\"name\": \"$2\"[^}]*\}"; }
gate_green() { gate_obj "$1" "$2" | sed -E 's/.*"green": (true|false).*/\1/'; }
gate_errors() { gate_obj "$1" "$2" | sed -E 's/.*"errors": "([^"]*)".*/\1/'; }
top_field() { printf '%s' "$1" | sed -nE "s/.*\"$2\": ([^,]*),.*/\1/p" | head -1; }

run_gates() { "$LOOP" gates "$1" "$CHANGE" 2>/dev/null; }

echo "=== specclaw-loop gates: review + verdict readers ==="
echo

# ── D1: review gate ───────────────────────────────────────────────────────────

# R1 — the reported failure. A clean APPROVED_WITH_NOTES report, byte-shaped like
# the one code-reviewer.md writes: the word BLOCK appears twice, in the summary
# count and in the rationale, but there is no [BLOCK] finding heading.
D="$WORK/r1"; make_specclaw "$D" true
cat > "$D/changes/$CHANGE/review-report.md" <<'EOF'
# Code Review Report: gate-fixture

**Reviewed:** 2026-08-10
**Model:** test
**Verdict:** APPROVED_WITH_NOTES

## Summary

4 findings: 0 BLOCK, 2 WARN, 2 NOTE

## Findings

### [WARN] a.sh:1 — Test quality
**Problem:** a warning.

### [NOTE] b.sh:2 — Naming
**Problem:** a note.

## Verdict Rationale

Zero BLOCK findings; APPROVED_WITH_NOTES.
EOF
J="$(run_gates "$D")"
assert_eq "R1 review gate green on a 0-BLOCK report (D1)" "true" "$(gate_green "$J" review)"
assert_eq "R1 review gate reports no errors" "" "$(gate_errors "$J" review)"
assert_eq "R1 all_green with every other gate green" "true" "$(top_field "$J" all_green)"
assert_eq "R1 passing_count is 4" "4" "$(top_field "$J" passing_count)"

# R2 — real blockers must still stop the loop, and the count must be the number
# of finding headings, not the number of times the word appears.
D="$WORK/r2"; make_specclaw "$D" true
cat > "$D/changes/$CHANGE/review-report.md" <<'EOF'
# Code Review Report: gate-fixture

**Verdict:** CHANGES_REQUESTED

## Summary

2 findings: 2 BLOCK, 0 WARN, 0 NOTE

## Findings

### [BLOCK] a.sh:1 — Correctness
**Problem:** off-by-one.
**Fix:** use <=.

### [BLOCK] b.sh:2 — Security
**Problem:** unquoted expansion.
**Fix:** quote it.

## Verdict Rationale

Two BLOCK findings, so CHANGES_REQUESTED.
EOF
J="$(run_gates "$D")"
assert_eq "R2 review gate red on real blockers" "false" "$(gate_green "$J" review)"
assert_eq "R2 counts headings, not word hits" "2 BLOCK-severity finding(s)" "$(gate_errors "$J" review)"
assert_eq "R2 all_green false" "false" "$(top_field "$J" all_green)"

# R3 — the "No findings." shape.
D="$WORK/r3"; make_specclaw "$D" true
cat > "$D/changes/$CHANGE/review-report.md" <<'EOF'
# Code Review Report: gate-fixture

**Verdict:** APPROVED

## Findings

No findings.
EOF
assert_eq "R3 review gate green on APPROVED" "true" "$(gate_green "$(run_gates "$D")" review)"

# R4 — malformed report: the verdict says blockers exist but no heading does.
# The verdict wins, so a truncated findings list cannot smuggle a change through.
D="$WORK/r4"; make_specclaw "$D" true
cat > "$D/changes/$CHANGE/review-report.md" <<'EOF'
# Code Review Report: gate-fixture

**Verdict:** CHANGES_REQUESTED

## Summary

3 findings: 3 BLOCK, 0 WARN, 0 NOTE
EOF
J="$(run_gates "$D")"
assert_eq "R4 verdict is authoritative when headings are missing" "false" "$(gate_green "$J" review)"
assert_eq "R4 names the verdict as the reason" "review verdict: CHANGES_REQUESTED" "$(gate_errors "$J" review)"

# R5 — absent report: required when code_review is on, ignored when off.
D="$WORK/r5a"; make_specclaw "$D" true
J="$(run_gates "$D")"
assert_eq "R5a missing report is red under code_review: true" "false" "$(gate_green "$J" review)"
assert_eq "R5a names the missing report" "no review-report.md yet" "$(gate_errors "$J" review)"

D="$WORK/r5b"; make_specclaw "$D" false
assert_eq "R5b missing report is green under code_review: false" "true" "$(gate_green "$(run_gates "$D")" review)"

# ── D2: extract_verdict ───────────────────────────────────────────────────────

# V1 — prose above the verdict line that contains a competing token. Under D2 the
# first match won and this PASS report failed its own gate.
D="$WORK/v1"; make_specclaw "$D" false
cat > "$D/changes/$CHANGE/verify-report.md" <<'EOF'
# Verification Report: gate-fixture

**Note:** the lint gate did not fail and no criterion is partial.

**Verdict:** PASS

## Summary

**Verdict:** PASS
EOF
J="$(run_gates "$D")"
assert_eq "V1 verdict line beats earlier prose (D2)" "true" "$(gate_green "$J" verify)"
assert_eq "V1 verify gate reports no errors" "" "$(gate_errors "$J" verify)"

# V2 — the inverse: a real PARTIAL must not be rescued by upbeat prose.
D="$WORK/v2"; make_specclaw "$D" false
cat > "$D/changes/$CHANGE/verify-report.md" <<'EOF'
# Verification Report: gate-fixture

All the unit criteria pass on the first attempt.

**Verdict:** PARTIAL

## Summary

E2E skipped, so AC4 is unverified.
EOF
J="$(run_gates "$D")"
assert_eq "V2 PARTIAL is not rescued by prose" "false" "$(gate_green "$J" verify)"
assert_eq "V2 names the verdict" "verify verdict: PARTIAL" "$(gate_errors "$J" verify)"

# V3 — FAIL still reads as FAIL.
D="$WORK/v3"; make_specclaw "$D" false
write_verify "$D" FAIL
assert_eq "V3 FAIL is red" "verify verdict: FAIL" "$(gate_errors "$(run_gates "$D")" verify)"

# V4 — a report predating the template has no Verdict line; the whole-file
# fallback keeps it resolving exactly as it did before this fix.
D="$WORK/v4"; make_specclaw "$D" false
cat > "$D/changes/$CHANGE/verify-report.md" <<'EOF'
# Verification Report: gate-fixture

Every acceptance criterion PASS after the rerun.
EOF
assert_eq "V4 legacy report with no Verdict line still resolves" "true" \
  "$(gate_green "$(run_gates "$D")" verify)"

# V5 — a report with neither a Verdict line nor any verdict token is UNKNOWN,
# never an accidental pass.
D="$WORK/v5"; make_specclaw "$D" false
printf '# Verification Report: gate-fixture\n\nNothing conclusive here.\n' \
  > "$D/changes/$CHANGE/verify-report.md"
J="$(run_gates "$D")"
assert_eq "V5 unreadable verdict is UNKNOWN and red" "verify verdict: UNKNOWN" "$(gate_errors "$J" verify)"

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
