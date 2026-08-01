#!/usr/bin/env bash
# run-phase-state-tests.sh — regression suite for bin/specclaw-set-phase, the one
# writer of a change's phase, and for the two `specclaw-status-row` defects that
# only surface once set-phase drives it against a stock status.md.
#
# What this pins:
#
#   AC1  a fresh change gets valid JSON with the right phase + phase record
#   AC2  the identical transition twice is byte-identical in both files
#   AC3  a backwards transition is refused and mutates nothing; --force wins
#   AC4  one `| PR |` row carrying the URL, `**GitHub Issue:**` untouched (NFR1)
#   E4   status.md absent → self-healed from templates/status.md
#   E5   status.md with no Progress table → standalone `**<label>:**` line, exit 0
#   E6   a status.md already corrupted with duplicate PR rows collapses to one
#   E8   an unknown phase is refused, lists the valid phases, writes nothing
#   E9   a --url full of literal pipes lands intact in both files
#   E10  verify → verify with a changed verdict is allowed and overwrites
#   plus a corrupt state.json (fail-open, FR7) and the python3 read fallback.
#
# and, for `bin/specclaw-reconcile` (FR8):
#
#   AC9  state.json says build while tasks.md is complete and verify-report.md
#        exists → drift, non-zero exit; --fix advances and exits 0
#   AC10 `gh` unavailable → the pr dimension is `unknown`, a recorded PR is not
#        cleared, and --fix names what it skipped
#   plus the `unknown` vs `none` distinction that AC10 turns on: a *failing* gh
#   is unknown (not drift, never actionable) while a *successful* gh finding no
#   PR is drift that --fix still refuses to adopt, because clearing a recorded
#   PR is a downgrade.
#
# Two of these double as defect pins for `specclaw-status-row`:
#
#   D3: a new row was inserted after the *last table row in the whole file*, so
#       against the shipped template a PR row landed in the **Agent Runs** table
#       instead of the Progress table. Pinned by AC4 and E4.
#   D4: the no-table fallback appended a fresh `**<label>:** …` line every run
#       instead of replacing the existing one, so AC2 did not hold for a
#       table-less status.md. Pinned by E5.
#
# Plain bash + coreutils only (jq is used when installed, python3 otherwise —
# exactly the optional-dependency rule set-phase itself follows). Run from
# anywhere:
#   bash plugins/specclaw/tests/run-phase-state-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
TEMPLATE="$(cd "$SCRIPT_DIR/.." && pwd)/templates/status.md"

SET_PHASE="$BIN_DIR/specclaw-set-phase"
STATUS_ROW="$BIN_DIR/specclaw-status-row"
RECONCILE="$BIN_DIR/specclaw-reconcile"

for f in "$SET_PHASE" "$STATUS_ROW" "$RECONCILE" "$TEMPLATE"; do
  if [[ ! -f "$f" ]]; then
    echo "FATAL: missing file: $f" >&2
    exit 2
  fi
done

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: this suite needs jq or python3 to read the JSON it asserts on" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SPECCLAW="$WORK/.specclaw"
mkdir -p "$SPECCLAW/changes"

PASS=0
FAIL=0
pass() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (= '$actual')"
  else
    fail "$label — expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label (contains '$needle')"
  else
    fail "$label — '$needle' not found in: $haystack"
  fi
}

assert_lacks() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$label (no '$needle')"
  else
    fail "$label — '$needle' should not appear, but does"
  fi
}

assert_same_file() {
  local label="$1" a="$2" b="$3"
  if cmp -s "$a" "$b"; then
    pass "$label"
  else
    fail "$label — files differ: $(diff "$a" "$b" | head -5 | tr '\n' ' ')"
  fi
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

RC=0
# run_sp <args…> — invoke set-phase, capture rc/stdout/stderr, never abort.
run_sp() {
  RC=0
  "$SET_PHASE" "$@" >"$WORK/last.out" 2>"$WORK/last.err" || RC=$?
}

# json_get <file> <dotted.path> — same optional-dependency rule as set-phase.
json_get() {
  local file="$1" path="$2"
  [[ -f "$file" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -rc ".${path} // empty" "$file" 2>/dev/null || true
  else
    python3 -c 'import json, sys
try:
    v = json.load(open(sys.argv[1]))
    for k in sys.argv[2].split("."):
        v = v[k]
except Exception:
    sys.exit(0)
if v is None:
    sys.exit(0)
sys.stdout.write(v if isinstance(v, str) else json.dumps(v, separators=(",", ":"), ensure_ascii=False))
' "$file" "$path" 2>/dev/null || true
  fi
}

json_ok() {
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$1" >/dev/null 2>&1
  else
    python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1
  fi
}

new_change() {
  local name="$1"
  mkdir -p "$SPECCLAW/changes/$name"
  printf '%s' "$SPECCLAW/changes/$name"
}

# A status.md in the shape the template renders to once a change is underway:
# a Progress table, a *second* table under `## Agent Runs`, and the
# `**GitHub Issue:**` line three integration scripts grep for (NFR1).
make_status() {
  cat >"$1" <<'EOF'
# Status: Tracker State Integrity

**Change:** tracker-state-integrity
**Started:** 2026-08-01
**Last Updated:** 2026-08-01

## Progress

| Phase | Status | Notes |
|-------|--------|-------|
| Proposal | ✅ Approved | Operator approved |
| Spec | ✅ Done | 9 FRs, 12 ACs |
| Design | ✅ Done | state.json + one writer |
| Tasks | ✅ Done | 7 tasks / 4 waves |
| Build | ✅ Done | 7/7 tasks |
| Verify | ✅ Passed | All 12 ACs |

## Task Progress

**Completed:** 7 / 7
**Failed:** 0

## Agent Runs

| Task | Agent | Model | Status | Duration |
|------|-------|-------|--------|----------|
| T1 | builder | sonnet | ✅ Done | 4m |
| T2 | builder | sonnet | ✅ Done | 6m |

## Issues

_None._

**GitHub Issue:** #56
EOF
}

# A status.md with no table at all — what edge case 5 describes.
make_bare_status() {
  cat >"$1" <<'EOF'
# Status: bare

**Change:** bare
**Started:** 2026-08-01

**GitHub Issue:** #56
EOF
}

URL="https://github.com/chan4lk/specclaw/pull/417"

# ─── AC1: a fresh change, no state.json ──────────────────────────────────────
C="$(new_change ac1)"
make_status "$C/status.md"
run_sp "$SPECCLAW" ac1 build done --tasks 7/11/0
assert_eq "AC1a exits 0" "0" "$RC"
if [[ -f "$C/state.json" ]]; then
  pass "AC1b state.json created"
else
  fail "AC1b state.json not created"
fi
if json_ok "$C/state.json"; then
  pass "AC1c state.json is valid JSON"
else
  fail "AC1c state.json is not valid JSON: $(cat "$C/state.json")"
fi
assert_eq "AC1d change recorded" "ac1" "$(json_get "$C/state.json" change)"
assert_eq "AC1e phase recorded" "build" "$(json_get "$C/state.json" phase)"
assert_eq "AC1f phases.build.status" "done" "$(json_get "$C/state.json" phases.build.status)"
assert_eq "AC1g phases.build.tasks" '{"done":7,"total":11,"failed":0}' \
  "$(json_get "$C/state.json" phases.build.tasks)"
AT="$(json_get "$C/state.json" phases.build.at)"
if [[ "$AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  pass "AC1h phases.build.at is a UTC timestamp (= '$AT')"
else
  fail "AC1h phases.build.at not a UTC timestamp: '$AT'"
fi
assert_eq "AC1i only the build record exists" "" "$(json_get "$C/state.json" phases.verify)"
assert_eq "AC1j Build row reflected into status.md" "| Build | ✅ Done | 7/11 tasks |" \
  "$(grep '^| Build |' "$C/status.md")"

# ─── AC2: the identical transition twice is byte-identical ───────────────────
C="$(new_change ac2)"
make_status "$C/status.md"
run_sp "$SPECCLAW" ac2 verify passed --verdict PASS --note "All 12 ACs"
assert_eq "AC2a first run exits 0" "0" "$RC"
cp "$C/state.json" "$WORK/ac2.state.snap"
cp "$C/status.md" "$WORK/ac2.status.snap"
run_sp "$SPECCLAW" ac2 verify passed --verdict PASS --note "All 12 ACs"
assert_eq "AC2b second run exits 0" "0" "$RC"
assert_same_file "AC2c state.json byte-identical" "$WORK/ac2.state.snap" "$C/state.json"
assert_same_file "AC2d status.md byte-identical" "$WORK/ac2.status.snap" "$C/status.md"

# ─── AC3: backwards transitions are refused, --force overrides ───────────────
C="$(new_change ac3)"
make_status "$C/status.md"
run_sp "$SPECCLAW" ac3 pr raised --url "$URL"
assert_eq "AC3a reaching pr exits 0" "0" "$RC"
cp "$C/state.json" "$WORK/ac3.state.snap"
cp "$C/status.md" "$WORK/ac3.status.snap"

run_sp "$SPECCLAW" ac3 build done
if [[ "$RC" -ne 0 ]]; then
  pass "AC3b build after pr exits non-zero (= $RC)"
else
  fail "AC3b build after pr should have been refused, exited 0"
fi
ERR="$(cat "$WORK/last.err")"
assert_contains "AC3c message names the recorded phase" "'pr'" "$ERR"
assert_contains "AC3d message names the requested phase" "'build'" "$ERR"
assert_contains "AC3e message points at --force" "--force" "$ERR"
assert_same_file "AC3f refused transition left state.json alone" "$WORK/ac3.state.snap" "$C/state.json"
assert_same_file "AC3g refused transition left status.md alone" "$WORK/ac3.status.snap" "$C/status.md"

run_sp "$SPECCLAW" ac3 build done --force
assert_eq "AC3h --force exits 0" "0" "$RC"
assert_eq "AC3i --force moved the phase back" "build" "$(json_get "$C/state.json" phase)"
assert_eq "AC3j the earlier pr record is retained" "raised" "$(json_get "$C/state.json" phases.pr.status)"
assert_eq "AC3k the pr record keeps its url" "$URL" "$(json_get "$C/state.json" phases.pr.url)"

# ─── AC4: one PR row with the URL, GitHub Issue line untouched ───────────────
# Also pins status-row defect D3: the row must land in the Progress table, not
# in the Agent Runs table further down the file.
C="$(new_change ac4)"
make_status "$C/status.md"
ISSUE_BEFORE="$(grep '^\*\*GitHub Issue:\*\*' "$C/status.md")"
AGENT_ROWS_BEFORE="$(grep -c '^| T[0-9] |' "$C/status.md")"
run_sp "$SPECCLAW" ac4 pr raised --url "$URL"
assert_eq "AC4a exits 0" "0" "$RC"
assert_eq "AC4b exactly one PR row" "1" "$(grep -c '^| PR |' "$C/status.md")"
assert_eq "AC4c the PR row carries the URL" "| PR | ✅ Raised | $URL |" \
  "$(grep '^| PR |' "$C/status.md")"
assert_eq "AC4d GitHub Issue line byte-unchanged (NFR1)" "$ISSUE_BEFORE" \
  "$(grep '^\*\*GitHub Issue:\*\*' "$C/status.md")"
assert_eq "AC4d2 exactly one GitHub Issue line, still the last line" "**GitHub Issue:** #56" \
  "$(tail -1 "$C/status.md")"
assert_eq "AC4e other Progress rows untouched" "| Verify | ✅ Passed | All 12 ACs |" \
  "$(grep '^| Verify |' "$C/status.md")"

PR_LN="$(grep -n '^| PR |' "$C/status.md" | head -1 | cut -d: -f1)"
AR_LN="$(grep -n '^## Agent Runs' "$C/status.md" | head -1 | cut -d: -f1)"
if [[ -n "$PR_LN" && -n "$AR_LN" && "$PR_LN" -lt "$AR_LN" ]]; then
  pass "AC4f/D3 the PR row is in the Progress table, above '## Agent Runs' (line $PR_LN < $AR_LN)"
else
  fail "AC4f/D3 the PR row landed at line $PR_LN, at or below '## Agent Runs' (line $AR_LN)"
fi
assert_eq "AC4g/D3 the PR row directly follows the last Progress row" \
  "| Verify | ✅ Passed | All 12 ACs |" "$(grep -B1 '^| PR |' "$C/status.md" | head -1)"
assert_eq "AC4h/D3 the Agent Runs table is unchanged" "$AGENT_ROWS_BEFORE" \
  "$(grep -c '^| T[0-9] |' "$C/status.md")"

# ─── Edge 4: status.md absent → self-healed from the template ────────────────
# The stock template carries two tables, so this is D3's other pin.
C="$(new_change edge4)"
run_sp "$SPECCLAW" edge4 pr raised --url "$URL"
assert_eq "E4a exits 0" "0" "$RC"
if [[ -f "$C/status.md" ]]; then
  pass "E4b status.md self-healed from the template"
else
  fail "E4b status.md not created"
fi
assert_contains "E4c warns that it created the file" "created from template" "$(cat "$WORK/last.err")"
assert_eq "E4d template placeholders are gone" "0" "$(grep -c '{{' "$C/status.md")"
assert_eq "E4e exactly one PR row" "1" "$(grep -c '^| PR |' "$C/status.md")"
PR_LN="$(grep -n '^| PR |' "$C/status.md" | head -1 | cut -d: -f1)"
AR_LN="$(grep -n '^## Agent Runs' "$C/status.md" | head -1 | cut -d: -f1)"
if [[ -n "$PR_LN" && -n "$AR_LN" && "$PR_LN" -lt "$AR_LN" ]]; then
  pass "E4f/D3 the PR row is inside the template's Progress table (line $PR_LN < $AR_LN)"
else
  fail "E4f/D3 the PR row landed at line $PR_LN, at or below '## Agent Runs' (line $AR_LN)"
fi
assert_eq "E4g/D3 the PR row directly follows the Verify row" "| Verify | - | - |" \
  "$(grep -B1 '^| PR |' "$C/status.md" | head -1)"

# ─── Edge 5: no Progress table → standalone field line, exit 0 ───────────────
# Also pins status-row defect D4: repeated runs must replace that line, not
# stack a second one beside it.
C="$(new_change edge5)"
make_bare_status "$C/status.md"
run_sp "$SPECCLAW" edge5 verify passed --verdict PASS
assert_eq "E5a no-table status.md is not a failure" "0" "$RC"
assert_eq "E5b standalone field line written" "**Verify:** PASS" \
  "$(grep '^\*\*Verify:\*\*' "$C/status.md")"
assert_eq "E5c state.json still written" "verify" "$(json_get "$C/state.json" phase)"
assert_eq "E5d GitHub Issue line survives" "1" "$(grep -c '^\*\*GitHub Issue:\*\* #56$' "$C/status.md")"

cp "$C/state.json" "$WORK/e5.state.snap"
cp "$C/status.md" "$WORK/e5.status.snap"
run_sp "$SPECCLAW" edge5 verify passed --verdict PASS
assert_eq "E5e/D4 re-running exits 0" "0" "$RC"
assert_same_file "E5f/D4 AC2 holds for a table-less status.md" "$WORK/e5.status.snap" "$C/status.md"
assert_same_file "E5g/D4 state.json still byte-identical" "$WORK/e5.state.snap" "$C/state.json"

run_sp "$SPECCLAW" edge5 verify failed --verdict FAIL
assert_eq "E5h/D4 a changed verdict exits 0" "0" "$RC"
assert_eq "E5i/D4 still exactly one Verify field line" "1" "$(grep -c '^\*\*Verify:\*\*' "$C/status.md")"
assert_eq "E5j/D4 the field line was replaced in place" "**Verify:** FAIL" \
  "$(grep '^\*\*Verify:\*\*' "$C/status.md")"

# ─── Edge 6: a status.md already corrupted with duplicate PR rows ────────────
C="$(new_change edge6)"
make_status "$C/status.md"
# The old `sed` address `/^\|…\|/a` matched every line, so the PR row was
# appended after all of them. Reproduce that shape exactly.
awk -v row="| PR | ✅ Raised | $URL |" '{ print; print row }' \
  "$C/status.md" >"$WORK/e6.corrupt" && mv "$WORK/e6.corrupt" "$C/status.md"
CORRUPT_ROWS="$(grep -c '^| PR |' "$C/status.md")"
if [[ "$CORRUPT_ROWS" -gt 10 ]]; then
  pass "E6a fixture starts corrupted ($CORRUPT_ROWS PR rows)"
else
  fail "E6a fixture should have many duplicate PR rows, has $CORRUPT_ROWS"
fi
run_sp "$SPECCLAW" edge6 pr raised --url "$URL"
assert_eq "E6b exits 0" "0" "$RC"
assert_eq "E6c duplicates collapsed to exactly one PR row" "1" "$(grep -c '^| PR |' "$C/status.md")"
assert_eq "E6d the surviving row carries the URL" "| PR | ✅ Raised | $URL |" \
  "$(grep '^| PR |' "$C/status.md")"
assert_eq "E6e GitHub Issue line survived the collapse" "1" \
  "$(grep -c '^\*\*GitHub Issue:\*\* #56$' "$C/status.md")"

# ─── Edge 8: an unknown phase writes nothing ─────────────────────────────────
C="$(new_change edge8)"
make_status "$C/status.md"
cp "$C/status.md" "$WORK/e8.status.snap"
run_sp "$SPECCLAW" edge8 shipped done
if [[ "$RC" -ne 0 ]]; then
  pass "E8a unknown phase exits non-zero (= $RC)"
else
  fail "E8a unknown phase should have been refused, exited 0"
fi
ERR="$(cat "$WORK/last.err")"
assert_contains "E8b message names the offending phase" "unknown phase: shipped" "$ERR"
assert_contains "E8c message lists the valid phases" "valid phases:" "$ERR"
assert_contains "E8d the list is the real phase order" "proposal spec design tasks build verify pr archived" "$ERR"
if [[ -f "$C/state.json" ]]; then
  fail "E8e no state.json should have been written"
else
  pass "E8e no state.json written"
fi
assert_same_file "E8f status.md untouched" "$WORK/e8.status.snap" "$C/status.md"

# ─── Edge 9: a --url full of literal pipes ───────────────────────────────────
C="$(new_change edge9)"
make_status "$C/status.md"
PIPE_URL='https://ex.com/p/1?a=b|c=[d]|e\f'
run_sp "$SPECCLAW" edge9 pr raised --url "$PIPE_URL"
assert_eq "E9a exits 0" "0" "$RC"
assert_eq "E9b the pipes survive into state.json" "$PIPE_URL" "$(json_get "$C/state.json" phases.pr.url)"
assert_eq "E9c the pipes survive into status.md" "| PR | ✅ Raised | $PIPE_URL |" \
  "$(grep '^| PR |' "$C/status.md")"
assert_eq "E9d still exactly one PR row" "1" "$(grep -c '^| PR |' "$C/status.md")"
assert_eq "E9e the Progress table gained exactly the PR row" \
  "Proposal Spec Design Tasks Build Verify PR" \
  "$(awk '/^## Progress/,/^## Task Progress/' "$C/status.md" |
    awk -F'|' '/^\|/ && $2 !~ /^-+$/ && $2 !~ /Phase/ { gsub(/^ +| +$/, "", $2); printf "%s%s", sep, $2; sep = " " }')"

# ─── Edge 10: verify → verify with a changed verdict ─────────────────────────
C="$(new_change edge10)"
make_status "$C/status.md"
run_sp "$SPECCLAW" edge10 verify failed --verdict FAIL --note "AC7 red"
assert_eq "E10a first verify exits 0" "0" "$RC"
assert_eq "E10b FAIL recorded" "FAIL" "$(json_get "$C/state.json" phases.verify.verdict)"
run_sp "$SPECCLAW" edge10 verify passed --verdict PASS --note "AC7 green"
assert_eq "E10c re-verify is allowed, not a backwards move" "0" "$RC"
assert_eq "E10d the verdict was overwritten" "PASS" "$(json_get "$C/state.json" phases.verify.verdict)"
assert_eq "E10e the status was overwritten" "passed" "$(json_get "$C/state.json" phases.verify.status)"
assert_eq "E10f status.md shows the new verdict" "| Verify | ✅ Passed | PASS — AC7 green |" \
  "$(grep '^| Verify |' "$C/status.md")"
assert_eq "E10g exactly one Verify row" "1" "$(grep -c '^| Verify |' "$C/status.md")"

# ─── FR7: a corrupt state.json must fail open, never block ───────────────────
C="$(new_change corrupt)"
make_status "$C/status.md"
printf '{"change":"corrupt","phase":"pr","phases":{"pr":{"status":"rai' >"$C/state.json"
run_sp "$SPECCLAW" corrupt build done --tasks 3/3/0
assert_eq "FR7a a truncated state.json does not block the transition" "0" "$RC"
if json_ok "$C/state.json"; then
  pass "FR7b the rewritten state.json is valid JSON"
else
  fail "FR7b state.json still unparseable: $(cat "$C/state.json")"
fi
assert_eq "FR7c phase recorded despite the corruption" "build" "$(json_get "$C/state.json" phase)"
assert_eq "FR7d the unreadable pr record was not copied forward" "" \
  "$(json_get "$C/state.json" phases.pr)"

C="$(new_change notjson)"
make_status "$C/status.md"
printf 'this is not json at all\n' >"$C/state.json"
run_sp "$SPECCLAW" notjson verify passed --verdict PASS
assert_eq "FR7e a non-JSON state.json does not block the transition" "0" "$RC"
if json_ok "$C/state.json"; then
  pass "FR7f the rewritten state.json is valid JSON"
else
  fail "FR7f state.json still unparseable: $(cat "$C/state.json")"
fi
assert_eq "FR7g phase recorded" "verify" "$(json_get "$C/state.json" phase)"

# ─── The python3 read fallback ───────────────────────────────────────────────
# set-phase prefers jq and falls back to python3. jq is absent on plenty of dev
# boxes (and on this one), so the fallback is the default path there — but the
# suite must exercise it either way. A PATH holding only the binaries set-phase
# and status-row need, minus jq, forces the fallback without skipping anything.
SHIM="$WORK/nojq-bin"
mkdir -p "$SHIM"
for b in bash sh env python3 date mktemp chmod mv cp rm mkdir tr sed awk cat dirname grep; do
  p="$(command -v "$b" 2>/dev/null)" || continue
  case "$p" in /*) ln -sf "$p" "$SHIM/$b" ;; esac
done
assert_eq "FBa the shim PATH really has no jq" "" "$(PATH="$SHIM" bash -c 'command -v jq' 2>/dev/null)"
if [[ -x "$SHIM/python3" ]]; then
  pass "FBb the shim PATH has python3"
else
  fail "FBb the shim PATH has no python3 — the fallback cannot be exercised"
fi

C="$(new_change fallback)"
make_status "$C/status.md"
RC=0
PATH="$SHIM" "$SET_PHASE" "$SPECCLAW" fallback build done --tasks 5/5/0 \
  >"$WORK/last.out" 2>"$WORK/last.err" || RC=$?
assert_eq "FBc jq-less write exits 0" "0" "$RC"
if json_ok "$C/state.json"; then
  pass "FBd jq-less write produced valid JSON"
else
  fail "FBd jq-less write produced invalid JSON: $(cat "$C/state.json")"
fi
assert_eq "FBe phase recorded via the python3 path" "build" "$(json_get "$C/state.json" phase)"

# The read fallback is what the monotonicity check and the record carry-forward
# depend on, so assert both under the same jq-less PATH.
RC=0
PATH="$SHIM" "$SET_PHASE" "$SPECCLAW" fallback pr raised --url "$URL" \
  >"$WORK/last.out" 2>"$WORK/last.err" || RC=$?
assert_eq "FBf forward move exits 0" "0" "$RC"
assert_eq "FBg the earlier build record was carried forward by the fallback reader" \
  '{"done":5,"total":5,"failed":0}' "$(json_get "$C/state.json" phases.build.tasks)"

RC=0
PATH="$SHIM" "$SET_PHASE" "$SPECCLAW" fallback build done --tasks 5/5/0 \
  >"$WORK/last.out" 2>"$WORK/last.err" || RC=$?
if [[ "$RC" -ne 0 ]]; then
  pass "FBh the fallback reader still enforces monotonicity (= $RC)"
else
  fail "FBh backwards move was allowed under the jq-less PATH"
fi

cp "$C/state.json" "$WORK/fb.state.snap"
cp "$C/status.md" "$WORK/fb.status.snap"
RC=0
PATH="$SHIM" "$SET_PHASE" "$SPECCLAW" fallback pr raised --url "$URL" \
  >"$WORK/last.out" 2>"$WORK/last.err" || RC=$?
assert_eq "FBi repeat under the jq-less PATH exits 0" "0" "$RC"
assert_same_file "FBj idempotent under the fallback reader (state.json)" \
  "$WORK/fb.state.snap" "$C/state.json"
assert_same_file "FBk idempotent under the fallback reader (status.md)" \
  "$WORK/fb.status.snap" "$C/status.md"

# ═════════════════════════════════════════════════════════════════════════════
# specclaw-reconcile (FR8, AC9, AC10)
# ═════════════════════════════════════════════════════════════════════════════
#
# Hermetic by construction: a second .specclaw tree under the same temp workdir
# (so the counts in the summary line are this section's alone), no network, and
# `gh` only ever reached through a shim on PATH. The three states that matter —
# gh absent, gh failing, gh answering — are three PATHs, not three mocks.

RSPEC="$WORK/.specclaw-recon"
mkdir -p "$RSPEC/changes"

# make_shim <dir> — a PATH holding only what reconcile, set-phase and status-row
# need. No jq (so every reconcile assertion below also exercises the python3
# read fallback) and, unless one is added afterwards, no gh.
make_shim() {
  local dir="$1" b p
  mkdir -p "$dir"
  for b in bash sh env python3 date mktemp chmod mv cp rm mkdir tr sed awk cat \
    dirname basename grep sort head tail cut wc find timeout git printf ls; do
    p="$(command -v "$b" 2>/dev/null)" || continue
    case "$p" in /*) ln -sf "$p" "$dir/$b" ;; esac
  done
}

NOGH="$WORK/recon-nogh"
GHFAIL="$WORK/recon-ghfail"
GHOK="$WORK/recon-ghok"
make_shim "$NOGH"
make_shim "$GHFAIL"
make_shim "$GHOK"

# A `gh` that always fails, the way an unauthenticated or offline one does.
cat >"$GHFAIL/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh: To get started with GitHub CLI, please run: gh auth login" >&2
exit 4
EOF
chmod +x "$GHFAIL/gh"

# A `gh` that succeeds, answering `pr list` with whatever SPECCLAW_TEST_PR_ROW
# holds — empty meaning "authenticated, and there is genuinely no PR".
cat >"$GHOK/gh" <<'EOF'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "pr list") ;;
  *) echo "gh shim: unsupported: $*" >&2; exit 1 ;;
esac
[ -n "${SPECCLAW_TEST_PR_ROW:-}" ] || exit 0
printf '%s\n' "$SPECCLAW_TEST_PR_ROW"
EOF
chmod +x "$GHOK/gh"

assert_eq "Ra the reconcile shims carry no jq" "" "$(PATH="$NOGH" bash -c 'command -v jq' 2>/dev/null)"
assert_eq "Rb the no-gh shim really has no gh" "" "$(PATH="$NOGH" bash -c 'command -v gh' 2>/dev/null)"

ROUT=""
# run_recon <shim_path> <args…>
run_recon() {
  local p="$1"
  shift
  RC=0
  PATH="$p" "$RECONCILE" "$@" >"$WORK/recon.out" 2>"$WORK/recon.err" || RC=$?
  ROUT="$(cat "$WORK/recon.out" "$WORK/recon.err")"
}

# run_sp_p <shim_path> <args…> — set-phase under a shim PATH, for building the
# fixtures the same way the lifecycle would.
run_sp_p() {
  local p="$1"
  shift
  RC=0
  PATH="$p" "$SET_PHASE" "$@" >"$WORK/last.out" 2>"$WORK/last.err" || RC=$?
}

rchange() {
  local name="$1"
  mkdir -p "$RSPEC/changes/$name"
  printf '%s' "$RSPEC/changes/$name"
}

# make_tasks <file> <done> <total> [failed] — the three markers reconcile greps.
make_tasks() {
  local f="$1" nd="$2" nt="$3" nf="${4:-0}" i n=1
  printf '# Tasks\n\n' >"$f"
  for ((i = 0; i < nd; i++)); do
    printf -- '- [x] `T%d` — done\n' "$n" >>"$f"
    n=$((n + 1))
  done
  for ((i = 0; i < nf; i++)); do
    printf -- '- [!] `T%d` — failed\n' "$n" >>"$f"
    n=$((n + 1))
  done
  while [ "$n" -le "$nt" ]; do
    printf -- '- [ ] `T%d` — pending\n' "$n" >>"$f"
    n=$((n + 1))
  done
}

make_verify_report() {
  cat >"$1" <<EOF
# Verify Report: $(basename "$(dirname "$1")")

**Date:** 2026-08-01

## Verdict: $2

Evidence elided.
EOF
}

# ─── R1: everything agrees → exit 0, no findings ─────────────────────────────
C="$(rchange clean)"
make_status "$C/status.md"
make_tasks "$C/tasks.md" 3 3
make_verify_report "$C/verify-report.md" PASS
run_sp_p "$NOGH" "$RSPEC" clean build done --tasks 3/3/0 --branch claude/clean
run_sp_p "$NOGH" "$RSPEC" clean verify passed --verdict PASS
cp "$C/state.json" "$WORK/r1.state.snap"

run_recon "$NOGH" "$RSPEC" clean
assert_eq "R1a an agreeing change exits 0" "0" "$RC"
assert_contains "R1b it reports no drift" "no drift" "$ROUT"
assert_lacks "R1c no DRIFT lines" "DRIFT" "$ROUT"
assert_same_file "R1d the report mode wrote nothing" "$WORK/r1.state.snap" "$C/state.json"

# ─── R2 / AC9: build recorded, reality is verified ───────────────────────────
C="$(rchange ac9)"
make_status "$C/status.md"
make_tasks "$C/tasks.md" 4 4
make_verify_report "$C/verify-report.md" PASS
run_sp_p "$NOGH" "$RSPEC" ac9 build done --tasks 2/4/0 --branch claude/ac9
assert_eq "R2a fixture recorded phase is build" "build" "$(json_get "$C/state.json" phase)"
cp "$C/state.json" "$WORK/r2.state.snap"

run_recon "$NOGH" "$RSPEC" ac9
if [[ "$RC" -ne 0 ]]; then
  pass "AC9a drift exits non-zero (= $RC)"
else
  fail "AC9a drift should exit non-zero, exited 0"
fi
assert_contains "AC9b the phase drift is named" "state.json says 'build'; observation supports 'verify'" "$ROUT"
assert_contains "AC9c the stale task counts are named" "state.json records 2/4" "$ROUT"
assert_contains "AC9d the observed counts are named" "tasks.md shows 4/4" "$ROUT"
assert_same_file "AC9e reporting drift changed nothing" "$WORK/r2.state.snap" "$C/state.json"

run_recon "$NOGH" "$RSPEC" ac9 --fix
assert_eq "AC9f --fix exits 0" "0" "$RC"
assert_eq "AC9g the phase advanced to verify" "verify" "$(json_get "$C/state.json" phase)"
assert_eq "AC9h the verdict was adopted from verify-report.md" "PASS" \
  "$(json_get "$C/state.json" phases.verify.verdict)"
assert_eq "AC9i the build record was refreshed from tasks.md" '{"done":4,"total":4,"failed":0}' \
  "$(json_get "$C/state.json" phases.build.tasks)"
# status.md only moves if set-phase did the write — reconcile never touches it.
assert_eq "AC9j --fix routed through set-phase: the Verify row was rewritten" \
  "| Verify | ✅ Passed | PASS |" "$(grep '^| Verify |' "$C/status.md")"
assert_eq "AC9k --fix routed through set-phase: the Build row too" \
  "| Build | ✅ Done | 4/4 tasks |" "$(grep '^| Build |' "$C/status.md")"

run_recon "$NOGH" "$RSPEC" ac9
assert_eq "AC9l the audit is idempotent: no drift after --fix" "0" "$RC"
assert_lacks "AC9m and no findings remain" "DRIFT" "$ROUT"

# ─── R3 / AC10: gh absent → unknown, and a recorded PR survives --fix ────────
C="$(rchange ac10)"
make_status "$C/status.md"
make_tasks "$C/tasks.md" 4 4
make_verify_report "$C/verify-report.md" PASS
run_sp_p "$NOGH" "$RSPEC" ac10 build done --tasks 4/4/0 --branch claude/ac10
run_sp_p "$NOGH" "$RSPEC" ac10 pr raised --url "$URL"
cp "$C/state.json" "$WORK/r3.state.snap"
cp "$C/status.md" "$WORK/r3.status.snap"

run_recon "$NOGH" "$RSPEC" ac10
assert_eq "AC10a an unobservable dimension is not drift" "0" "$RC"
assert_contains "AC10b the pr dimension reads unknown" "pr       unknown" "$ROUT"
assert_contains "AC10c and says why" "gh is not installed" "$ROUT"
assert_lacks "AC10d it never claims there is no PR" "gh finds no PR" "$ROUT"
assert_lacks "AC10e no drift is invented from the unknown" "DRIFT" "$ROUT"

run_recon "$NOGH" "$RSPEC" ac10 --fix
assert_eq "AC10f --fix exits 0" "0" "$RC"
assert_contains "AC10g --fix says it skipped the pr dimension" "SKIP     pr" "$ROUT"
assert_contains "AC10h and that the reason was 'unknown'" "observation is 'unknown'" "$ROUT"
assert_contains "AC10i and states the rule it is following" "never clears a recorded PR" "$ROUT"
assert_same_file "AC10j state.json is byte-identical after --fix" "$WORK/r3.state.snap" "$C/state.json"
assert_same_file "AC10k status.md is byte-identical after --fix" "$WORK/r3.status.snap" "$C/status.md"
assert_eq "AC10l the recorded pr phase survived untouched" "pr" "$(json_get "$C/state.json" phase)"
assert_eq "AC10m the recorded PR url was not cleared" "$URL" "$(json_get "$C/state.json" phases.pr.url)"

# ─── R4 / AC10: real drift alongside an unknown → fix one, skip the other ────
C="$(rchange ac10b)"
make_status "$C/status.md"
make_tasks "$C/tasks.md" 4 4
make_verify_report "$C/verify-report.md" FAIL
run_sp_p "$NOGH" "$RSPEC" ac10b build done --tasks 1/4/0 --branch claude/ac10b

run_recon "$NOGH" "$RSPEC" ac10b
if [[ "$RC" -ne 0 ]]; then
  pass "AC10n observable drift still exits non-zero with an unknown present (= $RC)"
else
  fail "AC10n observable drift alongside an unknown should exit non-zero"
fi

run_recon "$NOGH" "$RSPEC" ac10b --fix
assert_eq "AC10o --fix exits 0" "0" "$RC"
assert_eq "AC10p the observable dimensions were adopted" "verify" "$(json_get "$C/state.json" phase)"
assert_eq "AC10q including the FAIL verdict" "FAIL" "$(json_get "$C/state.json" phases.verify.verdict)"
assert_contains "AC10r the unknown pr dimension was still skipped out loud" "SKIP     pr" "$ROUT"
assert_eq "AC10s and no pr record was invented for it" "" "$(json_get "$C/state.json" phases.pr)"

# ─── R5: a failing gh is `unknown`, never `no PR` ────────────────────────────
# The distinction AC10 rests on. `gh` exiting 4 (auth) must read exactly like
# `gh` being absent — otherwise an unauthenticated laptop clears every PR it
# cannot see.
C="$(rchange ghfail)"
make_status "$C/status.md"
run_sp_p "$GHFAIL" "$RSPEC" ghfail pr raised --url "$URL" --branch claude/ghfail
cp "$C/state.json" "$WORK/r5.state.snap"

run_recon "$GHFAIL" "$RSPEC" ghfail
assert_eq "R5a a failing gh is not drift" "0" "$RC"
assert_contains "R5b the pr dimension reads unknown" "pr       unknown" "$ROUT"
assert_contains "R5c the exit status is reported" "gh exited 4" "$ROUT"
assert_lacks "R5d a failing gh never reads as 'no PR'" "gh finds no PR" "$ROUT"

run_recon "$GHFAIL" "$RSPEC" ghfail --fix
assert_eq "R5e --fix exits 0" "0" "$RC"
assert_same_file "R5f --fix left the recorded PR alone" "$WORK/r5.state.snap" "$C/state.json"

# ─── R6: a *succeeding* gh finding no PR is drift — and still not adopted ────
# `none` is a real observation, so it is reported. Adopting it would mean
# pr → verify, a downgrade; reconcile refuses and says so rather than passing
# --force behind the operator's back.
C="$(rchange ghnone)"
make_status "$C/status.md"
run_sp_p "$GHOK" "$RSPEC" ghnone pr raised --url "$URL" --branch claude/ghnone
cp "$C/state.json" "$WORK/r6.state.snap"

export SPECCLAW_TEST_PR_ROW=""
run_recon "$GHOK" "$RSPEC" ghnone
if [[ "$RC" -ne 0 ]]; then
  pass "R6a an authenticated gh finding no PR is drift (= $RC)"
else
  fail "R6a gh answering 'no PR' against a recorded one should be drift"
fi
assert_contains "R6b the pr dimension reads none, not unknown" "none — gh finds no PR" "$ROUT"
assert_contains "R6c the finding names the recorded url" "state.json records a PR (${URL})" "$ROUT"

run_recon "$GHOK" "$RSPEC" ghnone --fix
assert_eq "R6d --fix exits 0" "0" "$RC"
assert_contains "R6e --fix refuses to clear the PR" "clearing a recorded PR is a downgrade" "$ROUT"
assert_contains "R6e2 a --fix that applied nothing says so, so exit 0 cannot read as clean" \
  "finding(s) found, none applied" "$ROUT"
assert_same_file "R6f the recorded PR is still there" "$WORK/r6.state.snap" "$C/state.json"
assert_eq "R6g the phase is still pr" "pr" "$(json_get "$C/state.json" phase)"

# ─── R7: a succeeding gh that finds a PR → drift, and --fix adopts it ────────
C="$(rchange ghok)"
make_status "$C/status.md"
make_tasks "$C/tasks.md" 2 2
make_verify_report "$C/verify-report.md" PASS
run_sp_p "$GHOK" "$RSPEC" ghok build done --tasks 2/2/0 --branch feature/odd-name
run_sp_p "$GHOK" "$RSPEC" ghok verify passed --verdict PASS

PR_URL_OBS="https://github.com/chan4lk/specclaw/pull/417"
export SPECCLAW_TEST_PR_ROW="2026-08-01T10:00:00Z 417 OPEN ${PR_URL_OBS}"
run_recon "$GHOK" "$RSPEC" ghok
if [[ "$RC" -ne 0 ]]; then
  pass "R7a an unrecorded open PR is drift (= $RC)"
else
  fail "R7a an unrecorded open PR should be drift"
fi
assert_contains "R7b the PR is reported with its number and state" "#417 open" "$ROUT"
assert_contains "R7c the finding names the recorded branch, not a prefix guess" \
  "on 'feature/odd-name'; state.json records no PR" "$ROUT"

run_recon "$GHOK" "$RSPEC" ghok --fix
assert_eq "R7d --fix exits 0" "0" "$RC"
assert_eq "R7e the phase advanced to pr" "pr" "$(json_get "$C/state.json" phase)"
assert_eq "R7f the observed url was recorded" "$PR_URL_OBS" "$(json_get "$C/state.json" phases.pr.url)"
assert_eq "R7g --fix routed through set-phase: one PR row in status.md" "1" \
  "$(grep -c '^| PR |' "$C/status.md")"
assert_eq "R7h the PR row carries the url" "| PR | ✅ Raised | $PR_URL_OBS |" \
  "$(grep '^| PR |' "$C/status.md")"
unset SPECCLAW_TEST_PR_ROW

# ─── R8: no state.json at all is "unmanaged", not drift ──────────────────────
C="$(rchange unmanaged)"
make_status "$C/status.md"
printf '# Proposal\n' >"$C/proposal.md"
make_tasks "$C/tasks.md" 2 5
run_recon "$NOGH" "$RSPEC" unmanaged
assert_eq "R8a an unmanaged change exits 0" "0" "$RC"
assert_contains "R8b it is reported as unmanaged" "unmanaged — no state.json" "$ROUT"
assert_contains "R8c and explicitly not as drift" "no drift (unmanaged)" "$ROUT"
assert_lacks "R8d no findings are raised against it" "DRIFT" "$ROUT"

run_recon "$NOGH" "$RSPEC" unmanaged --fix
assert_eq "R8e --fix on an unmanaged change exits 0" "0" "$RC"
if [[ -f "$C/state.json" ]]; then
  fail "R8f --fix must not backfill state.json for an unmanaged change (AC6 rendering)"
else
  pass "R8f --fix left the unmanaged change unmanaged"
fi

# ─── R9: a corrupt state.json is drift, and --fix rewrites it ────────────────
C="$(rchange broken)"
make_status "$C/status.md"
make_tasks "$C/tasks.md" 3 3
printf '{"change":"broken","phase":"bui' >"$C/state.json"
run_recon "$NOGH" "$RSPEC" broken
if [[ "$RC" -ne 0 ]]; then
  pass "R9a an unparseable state.json is drift (= $RC)"
else
  fail "R9a an unparseable state.json should be drift"
fi
assert_contains "R9b it is named as unreadable, not treated as unmanaged" \
  "state.json does not parse" "$ROUT"
run_recon "$NOGH" "$RSPEC" broken --fix
assert_eq "R9c --fix exits 0" "0" "$RC"
if json_ok "$C/state.json"; then
  pass "R9d --fix rewrote it as valid JSON"
else
  fail "R9d state.json still unparseable: $(cat "$C/state.json")"
fi
assert_eq "R9e with the observed phase" "build" "$(json_get "$C/state.json" phase)"

# ─── R10: sweeping every change, and skipping archive/ ───────────────────────
mkdir -p "$RSPEC/changes/archive/2026-07-01-old"
printf '{"change":"2026-07-01-old","phase":"nonsense","phases":{}}\n' \
  >"$RSPEC/changes/archive/2026-07-01-old/state.json"
make_tasks "$RSPEC/changes/archive/2026-07-01-old/tasks.md" 9 9

run_recon "$NOGH" "$RSPEC"
assert_lacks "R10a archived changes are skipped (edge 7)" "2026-07-01-old" "$ROUT"
assert_lacks "R10b and the archive directory is not itself a change" "▸ archive" "$ROUT"
assert_contains "R10c the sweep covers every active change" "examined: 9" "$ROUT"
assert_contains "R10d and counts the unmanaged one separately" "unmanaged: 1" "$ROUT"

run_recon "$NOGH" "$RSPEC" 2026-07-01-old
assert_eq "R10e naming an archived change is a usage error" "2" "$RC"

run_recon "$NOGH" "$RSPEC" no-such-change
assert_eq "R10f naming an unknown change is a usage error" "2" "$RC"
assert_contains "R10g with a message naming it" "no such change: no-such-change" "$ROUT"

# ─── S: the renderer — specclaw-update-status against state.json (AC5–AC7) ───
#
# The writer and the auditor were covered above; the *reader* is the third side
# of the contract and the one a user actually looks at. These three cases were
# proved by hand during verify, which is exactly why they belong here: a hand
# proof does not run in CI.
#
# Every case runs under the no-gh shim with SPECCLAW_STATUS_NO_PR=1, so the
# rendered line is a pure function of the fixture — no network, no clock beyond
# the `Last Updated` header, which no assertion reads.

USTATUS="$BIN_DIR/specclaw-update-status"
if [[ ! -f "$USTATUS" ]]; then
  fail "Sa specclaw-update-status exists"
else
  USPEC="$WORK/.specclaw-render"
  mkdir -p "$USPEC/changes"
  cat >"$USPEC/config.yaml" <<'EOF'
version: 1
project:
  name: "render-fixture"
git:
  branch_prefix: "specclaw/"
EOF

  SOUT=""
  SERR=""
  # run_us — regenerate STATUS.md, capture rc and stderr, read back the dashboard.
  run_us() {
    RC=0
    PATH="$NOGH" SPECCLAW_STATUS_NO_PR=1 "$USTATUS" "$USPEC" \
      >"$WORK/us.out" 2>"$WORK/us.err" || RC=$?
    SERR="$(cat "$WORK/us.err")"
    SOUT="$(cat "$USPEC/STATUS.md" 2>/dev/null || true)"
  }

  # line_for <change> — the one dashboard bullet naming this change.
  line_for() {
    grep -F -- "**$1**" "$USPEC/STATUS.md" 2>/dev/null | head -1
  }

  # AC5 — a recorded `pr` phase renders as PR-in-review with no network reachable.
  # Pre-change this rendered `✅ … 2/2 tasks`, indistinguishable from "build done",
  # which is the whole reason state.json exists.
  mkdir -p "$USPEC/changes/recorded"
  make_tasks "$USPEC/changes/recorded/tasks.md" 2 2
  run_sp_p "$NOGH" "$USPEC" recorded build done --tasks 2/2/0
  run_sp_p "$NOGH" "$USPEC" recorded pr raised --url "$URL"
  run_us
  assert_eq "S1a rendering a recorded phase exits 0" "0" "$RC"
  assert_eq "S1b the pr phase leads the line, counts follow" \
    "- 🔀 **recorded** — pr raised | 2/2 tasks (100%) | 0 failed" "$(line_for recorded)"
  assert_lacks "S1c and it is not rendered as a finished build" \
    "✅ **recorded**" "$SOUT"
  assert_eq "S1d a recorded phase needs no gh at all" "" "$SERR"

  # The `pr` qualifier comes from phases.pr.status. phases.pr.state is written by
  # nothing, so a renderer reading it would silently print a bare `pr`.
  assert_eq "S1e the qualifier is the recorded status, not an unwritten field" \
    "raised" "$(json_get "$USPEC/changes/recorded/state.json" phases.pr.status)"
  assert_eq "S1f nothing writes phases.pr.state" \
    "" "$(json_get "$USPEC/changes/recorded/state.json" phases.pr.state)"

  # AC6 — no state.json: byte-for-byte the pre-change checkbox inference, and no
  # warning. Every change that predates this feature takes this path.
  mkdir -p "$USPEC/changes/unmanaged"
  make_tasks "$USPEC/changes/unmanaged/tasks.md" 1 2
  run_us
  assert_eq "S2a a change with no state.json still renders" "0" "$RC"
  assert_eq "S2b via checkbox inference, exactly as before the change" \
    "- 🔨 **unmanaged** — 1/2 tasks (50%) | 0 failed" "$(line_for unmanaged)"
  assert_eq "S2c and silently — an absent state.json is not a fault" "" "$SERR"

  # AC7 — corrupt state.json: fall back, warn, exit 0. A half-written file must
  # never be believed, and must never take the dashboard down with it.
  mkdir -p "$USPEC/changes/corrupt"
  make_tasks "$USPEC/changes/corrupt/tasks.md" 1 2
  printf '%s' '{"change":"corrupt","phase":"pr","phas' \
    >"$USPEC/changes/corrupt/state.json"
  run_us
  assert_eq "S3a a corrupt state.json still exits 0" "0" "$RC"
  assert_contains "S3b with a warning naming the change" \
    "unreadable state.json for corrupt" "$SERR"
  assert_eq "S3c and renders via inference, not the phase it half-claims" \
    "- 🔨 **corrupt** — 1/2 tasks (50%) | 0 failed" "$(line_for corrupt)"
  assert_lacks "S3d the truncated 'pr' is not believed" "🔀 **corrupt**" "$SOUT"

  # Not JSON at all — the other corruption shape, same contract.
  printf '%s' 'garbage not json' >"$USPEC/changes/corrupt/state.json"
  run_us
  assert_eq "S3e non-JSON content is handled identically" "0" "$RC"
  assert_eq "S3f and renders identically" \
    "- 🔨 **corrupt** — 1/2 tasks (50%) | 0 failed" "$(line_for corrupt)"

  # Edge case 7 — a corrupt state.json under archive/ is never read at all.
  mkdir -p "$USPEC/changes/archive/2026-01-01-gone"
  make_tasks "$USPEC/changes/archive/2026-01-01-gone/tasks.md" 3 3
  printf '%s' 'totally broken {{{' \
    >"$USPEC/changes/archive/2026-01-01-gone/state.json"
  run_us
  assert_eq "S4a an archived change's state.json is never read" "0" "$RC"
  assert_lacks "S4b so it raises no warning" "2026-01-01-gone" "$SERR"
fi

# ─── E11: a change name with sed metacharacters ──────────────────────────────
#
# The template self-heal interpolates the change name into a sed *replacement*,
# where `&` means "the whole match" and `/` closes the expression. An unescaped
# name here wrote `{{title}}` back as the literal `{{title}}` (for `&`) or
# aborted the run outright (for `/`), after state.json was already written.

C="$(new_change 'a&b')"
run_sp "$SPECCLAW" 'a&b' build done --tasks 1/1/0
assert_eq "E11a a change name containing & is written" "0" "$RC"
assert_eq "E11b state.json records it verbatim" "a&b" "$(json_get "$C/state.json" change)"
assert_contains "E11c and the template title is the name, not the match" \
  "a&b" "$(head -3 "$C/status.md" 2>/dev/null)"
assert_lacks "E11d with no unsubstituted placeholder left behind" \
  "{{title}}" "$(cat "$C/status.md" 2>/dev/null)"

# ─── Hermeticity: nothing was written outside the temp workdir ───────────────
assert_eq "Ha every change directory lives under the temp workdir" "0" \
  "$(find "$SPECCLAW" "$RSPEC" ${USPEC:+"$USPEC"} -name state.json -not -path "$WORK/*" | wc -l)"

echo
echo "─────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
