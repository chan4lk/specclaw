#!/usr/bin/env bash
# run-parser-tests.sh — regression suite for specclaw's bin parsers.
#
# Locks in the recently fixed behaviors:
#   B2: validate-change task counting ignores ``` fenced blocks and only
#       counts backtick-wrapped `T<n>` ids.
#   B3: verify collect parses ACs as AC1 / AC-1, with/without `- [ ]`,
#       with/without **bold**.
#   B4: verify collect parses `Files:` lines that begin with a `  - ` bullet.
# Plus NFR2: existing in-repo change docs still parse (no regression).
#
# Plain bash only — no bats/npm. Run from anywhere:
#   bash plugins/specclaw/tests/run-parser-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

# --- Resolve own dir and locate ../bin ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PARSE_TASKS="$BIN_DIR/specclaw-parse-tasks"
VALIDATE_CHANGE="$BIN_DIR/specclaw-validate-change"
VERIFY="$BIN_DIR/specclaw-verify"

for b in "$PARSE_TASKS" "$VALIDATE_CHANGE" "$VERIFY"; do
  if [[ ! -x "$b" && ! -f "$b" ]]; then
    echo "FATAL: missing bin script: $b" >&2
    exit 2
  fi
done

# --- mktemp workspace with a real .specclaw-like layout (changes/<name>/) ---
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# assert_eq <label> <expected> <actual>
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (= '$actual')"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

# Build a change dir under the temp workspace and echo its specclaw_dir.
# Usage: make_change <change_name> [spec_fixture] [tasks_fixture]
make_change() {
  local name="$1" spec="${2:-}" tasks="${3:-}"
  local cdir="$WORK/changes/$name"
  mkdir -p "$cdir"
  [[ -n "$spec" ]] && cp "$FIXTURES_DIR/$spec" "$cdir/spec.md"
  [[ -n "$tasks" ]] && cp "$FIXTURES_DIR/$tasks" "$cdir/tasks.md"
  echo "$cdir"
}

echo "=== specclaw bin parser regression suite ==="
echo "bin:      $BIN_DIR"
echo "fixtures: $FIXTURES_DIR"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 1 — parse-tasks finds exactly the real T-tasks (template Legend +
# fenced `T<n>` placeholder are not numeric ids, so they are not picked up).
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 1: parse-tasks finds exactly the real T-tasks ---"
c1="$(make_change c1-tasks "" tasks.md)"
ids="$("$PARSE_TASKS" "$c1/tasks.md" | jq -r '[.[].id] | sort | join(",")')"
assert_eq "parse-tasks task ids" "T1,T2,T3" "$ids"
# Statuses round-trip correctly for the three markers.
st="$("$PARSE_TASKS" "$c1/tasks.md" | jq -r '[.[] | .status] | join(",")')"
assert_eq "parse-tasks statuses (x,space,~)" "complete,pending,in_progress" "$st"
# --validate exits 0 on well-formed output.
if "$PARSE_TASKS" --validate "$c1/tasks.md" >/dev/null 2>&1; then
  pass "parse-tasks --validate exits 0"
else
  fail "parse-tasks --validate exits 0"
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 2 — B2: validate-change `status` counts only real backtick T-ids,
# excluding the fenced block (numeric `T9`/`T8` examples) and bare legend lines.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 2 (B2): validate-change status excludes fence + legend ---"
c2="$(make_change b2-fence "" tasks-fenced-id.md)"
line="$("$VALIDATE_CHANGE" "$WORK" b2-fence status | grep -o 'tasks.md ([0-9]*/[0-9]* complete)')"
# Real tasks: T1 [x], T2 [ ] -> 1 complete of 2 total. Fenced T9/T8 ignored.
assert_eq "B2 status line" "tasks.md (1/2 complete)" "$line"

# Same fixture against the c1 tasks (which has 3 real tasks, 1 complete) to
# confirm counting tracks the real markers and not the fenced placeholder.
line1="$("$VALIDATE_CHANGE" "$WORK" c1-tasks status | grep -o 'tasks.md ([0-9]*/[0-9]* complete)')"
assert_eq "B2 status line (case-1 tasks)" "tasks.md (1/3 complete)" "$line1"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 3 — B3: verify collect parses all three AC formats.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 3 (B3): verify collect parses mixed AC formats ---"
c3="$(make_change b3-ac spec.md tasks.md)"
ac_count="$("$VERIFY" collect "$WORK" b3-ac 2>/dev/null | jq '.acceptance_criteria | length')"
assert_eq "AC count" "3" "$ac_count"
# Each AC line is non-empty and the AC ids are all represented.
ac_join="$("$VERIFY" collect "$WORK" b3-ac 2>/dev/null | jq -r '.acceptance_criteria | join("\n")')"
for needle in "AC-1" "AC2" "AC-3"; do
  if grep -q "$needle" <<<"$ac_join"; then
    pass "AC contains $needle"
  else
    fail "AC contains $needle"
  fi
done
empty_acs="$("$VERIFY" collect "$WORK" b3-ac 2>/dev/null | jq '[.acceptance_criteria[] | select(. == "")] | length')"
assert_eq "no empty AC entries" "0" "$empty_acs"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 4 — B4: verify collect parses `  - Files:` bullet lines.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 4 (B4): verify collect parses bulleted Files: lines ---"
# Reuse the b3-ac change (its tasks.md has `  - Files:` bullets with backticks).
paths="$("$VERIFY" collect "$WORK" b3-ac 2>/dev/null | jq -r '[.changed_files[].path] | sort | join(",")')"
assert_eq "changed_files paths" "src/a.ts,src/b.ts,src/c.ts,src/d.ts" "$paths"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 5 — NFR2: existing in-repo change still parses (no regression).
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 5 (NFR2): real in-repo change still parses ---"
REAL_SPECCLAW="$REPO_ROOT/.specclaw"
REAL_CHANGE="build-engine"
if [[ ! -f "$REAL_SPECCLAW/changes/$REAL_CHANGE/spec.md" ]]; then
  # Fallback: pick any change that has both spec.md and tasks.md.
  for d in "$REAL_SPECCLAW"/changes/*/; do
    if [[ -f "$d/spec.md" && -f "$d/tasks.md" ]]; then
      REAL_CHANGE="$(basename "$d")"
      break
    fi
  done
fi

if [[ -f "$REAL_SPECCLAW/changes/$REAL_CHANGE/spec.md" && -f "$REAL_SPECCLAW/changes/$REAL_CHANGE/tasks.md" ]]; then
  echo "    using real change: $REAL_CHANGE"
  real_ids="$("$PARSE_TASKS" "$REAL_SPECCLAW/changes/$REAL_CHANGE/tasks.md" | jq 'length')"
  if [[ "$real_ids" -gt 0 ]]; then
    pass "NFR2 parse-tasks found $real_ids tasks in $REAL_CHANGE"
  else
    fail "NFR2 parse-tasks found 0 tasks in $REAL_CHANGE"
  fi
  real_acs="$("$VERIFY" collect "$REAL_SPECCLAW" "$REAL_CHANGE" 2>/dev/null | jq '.acceptance_criteria | length')"
  if [[ "$real_acs" -gt 0 ]]; then
    pass "NFR2 verify collect found $real_acs ACs in $REAL_CHANGE"
  else
    fail "NFR2 verify collect found 0 ACs in $REAL_CHANGE"
  fi
else
  fail "NFR2 could not locate a real change with spec.md + tasks.md under $REAL_SPECCLAW"
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 6 — grounded-context: specclaw-discover-context ranking, filtering,
# budget, and off-switch (all jq-free; runs in a non-git temp tree, which also
# exercises the find fallback).
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 6: discover-context ranking / filtering / budget ---"
DISCOVER="$BIN_DIR/specclaw-discover-context"
if [[ ! -f "$DISCOVER" ]]; then
  fail "discover-context script missing at $DISCOVER"
else
  # Fixture project: copy the static tree, add a .specclaw dir per sub-case.
  DPROJ="$WORK/discovery-proj"
  mkdir -p "$DPROJ/.specclaw"
  cp -R "$FIXTURES_DIR/discovery/." "$DPROJ/"
  printf 'context:\n  discovery: true\n' > "$DPROJ/.specclaw/config.yaml"

  # 6a (AC1/AC2) — ranking: llms.txt-listed guide.md first (tier 1), root
  # canonical CLAUDE/README (tier 2), nested src/README (tier 4).
  paths="$(bash "$DISCOVER" "$DPROJ/.specclaw" list 2>/dev/null | cut -f3 | tr '\n' ',')"
  assert_eq "6a ranked order" "docs/guide.md,CLAUDE.md,README.md,docs/skip.md,src/README.md," "$paths"

  # 6b (AC2) — missing llms.txt entry warns but does not fail.
  if bash "$DISCOVER" "$DPROJ/.specclaw" list 2>&1 >/dev/null | grep -q "docs/nope.md"; then
    pass "6b llms.txt missing entry warned"
  else
    fail "6b llms.txt missing entry warned"
  fi

  # 6c (AC3) — defaults exclude CHANGELOG.md and archive/.
  listed="$(bash "$DISCOVER" "$DPROJ/.specclaw" list 2>/dev/null | cut -f3)"
  if grep -q "CHANGELOG.md" <<<"$listed" || grep -q "archive/old.md" <<<"$listed"; then
    fail "6c default exclusions (CHANGELOG/archive leaked)"
  else
    pass "6c default exclusions"
  fi

  # 6d (AC4) — precedence: folders includes docs/, exclude still beats it;
  # root-relative pattern excludes root README.
  printf 'context:\n  discovery: true\n  folders:\n    - "docs"\n  exclude:\n    - "docs/skip.md"\n' > "$DPROJ/.specclaw/config.yaml"
  paths="$(bash "$DISCOVER" "$DPROJ/.specclaw" list 2>/dev/null | cut -f3 | tr '\n' ',')"
  assert_eq "6d exclude beats folders" "docs/guide.md," "$paths"
  printf 'context:\n  discovery: true\n  exclude:\n    - "./README.md"\n    - "src"\n' > "$DPROJ/.specclaw/config.yaml"
  paths="$(bash "$DISCOVER" "$DPROJ/.specclaw" list 2>/dev/null | cut -f3 | tr '\n' ',')"
  assert_eq "6d root-relative + segment excludes" "docs/guide.md,CLAUDE.md,docs/skip.md," "$paths"

  # 6e (AC5) — budget: emit stays within budget and names every casualty.
  printf 'context:\n  discovery: true\n' > "$DPROJ/.specclaw/config.yaml"
  out="$(bash "$DISCOVER" "$DPROJ/.specclaw" emit --budget 4 2>/dev/null)"
  if grep -q '^<!-- dropped (over 4-line budget):' <<<"$out"; then
    pass "6e budget footer present"
  else
    fail "6e budget footer present"
  fi
  # Budget 4: guide.md (2) + CLAUDE.md (2) fit exactly; the rest must be
  # named as dropped. " README.md" (leading space) avoids matching src/README.md.
  for casualty in " README.md" "docs/skip.md" "src/README.md"; do
    if grep "^<!-- dropped" <<<"$out" | grep -q "$casualty"; then
      pass "6e names dropped:$casualty"
    else
      fail "6e names dropped:$casualty"
    fi
  done

  # 6f (AC6) — discovery off: zero output, exit 0.
  printf 'context:\n  discovery: false\n' > "$DPROJ/.specclaw/config.yaml"
  out="$(bash "$DISCOVER" "$DPROJ/.specclaw" emit 2>/dev/null)"; rc=$?
  if [[ -z "$out" && "$rc" -eq 0 ]]; then
    pass "6f discovery off = empty output, exit 0"
  else
    fail "6f discovery off = empty output, exit 0 (rc=$rc, ${#out} bytes)"
  fi

  # 6g — git enumeration path: run against the real repo, expect README.md
  # (tier 2) present and .specclaw/ absent.
  real_list="$(bash "$DISCOVER" "$REPO_ROOT/.specclaw" list 2>/dev/null | cut -f3)"
  if grep -qx "README.md" <<<"$real_list" && ! grep -q "^\.specclaw/" <<<"$real_list"; then
    pass "6g git-tree enumeration on real repo"
  else
    fail "6g git-tree enumeration on real repo"
  fi
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo "=================================================="
echo "$PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
