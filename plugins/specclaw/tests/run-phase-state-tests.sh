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

for f in "$SET_PHASE" "$STATUS_ROW" "$TEMPLATE"; do
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

# ─── Hermeticity: nothing was written outside the temp workdir ───────────────
assert_eq "Ha every change directory lives under the temp workdir" "0" \
  "$(find "$SPECCLAW" -name state.json -not -path "$WORK/*" | wc -l)"

echo
echo "─────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
