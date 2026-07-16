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
# Case 7 — smart-base-branch: detect_base_branch chain + base-aware setup.
# Local bare origin with default branch 'develop'; jq-free asserts.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 7: base branch detection + base-aware setup ---"
BUILD_BIN="$BIN_DIR/specclaw-build"
GPROJ="$WORK/base-branch-proj"

# Build a bare origin whose default branch is 'develop'
mkdir -p "$WORK/origin-src" && (
  cd "$WORK/origin-src"
  git init -q -b develop .
  git config user.email t@t && git config user.name t
  echo base > base.txt && git add . && git commit -qm base
  echo dev2 > dev2.txt && git add . && git commit -qm dev2
) && git clone -q --bare "$WORK/origin-src" "$WORK/origin.git" && (
  git -C "$WORK/origin.git" symbolic-ref HEAD refs/heads/develop
) && git clone -q "$WORK/origin.git" "$GPROJ" && (
  cd "$GPROJ"
  git config user.email t@t && git config user.name t
  mkdir -p .specclaw/changes/bb-test
  printf 'version: 1\ngit:\n  strategy: "branch-per-change"\n  branch_prefix: "specclaw/"\n' > .specclaw/config.yaml
  printf '# t\n- [ ] `T1` — x\n  - Files: a\n' > .specclaw/changes/bb-test/tasks.md
)

if [[ ! -f "$BUILD_BIN" ]]; then
  fail "specclaw-build missing"
else
  # 7a (AC1) — detection resolves origin/HEAD -> develop; setup JSON reports it
  setup_json="$(cd "$GPROJ" && bash "$BUILD_BIN" setup .specclaw bb-test 2>/dev/null)"
  base_val="$(printf '%s' "$setup_json" | grep -o '"base_branch": "[^"]*"' | sed 's/.*: "//;s/"//')"
  assert_eq "7a detected base (origin/HEAD)" "develop" "$base_val"

  # 7b (AC4) — new change branch starts at origin/develop tip
  tip_origin="$(git -C "$GPROJ" rev-parse origin/develop)"
  tip_branch="$(git -C "$GPROJ" rev-parse specclaw/bb-test)"
  assert_eq "7b branch starts at origin/develop tip" "$tip_origin" "$tip_branch"

  # 7c (AC5) — resume path unchanged (second run warns, same branch)
  resume_out="$(cd "$GPROJ" && bash "$BUILD_BIN" setup .specclaw bb-test 2>&1 >/dev/null)"
  if grep -q "already exists — resuming" <<<"$resume_out"; then
    pass "7c resume warning intact"
  else
    fail "7c resume warning intact"
  fi

  # 7d (AC2) — config override beats origin/HEAD
  (cd "$GPROJ" && git checkout -q develop && git branch -q -D specclaw/bb-test)
  printf 'version: 1\ngit:\n  strategy: "branch-per-change"\n  branch_prefix: "specclaw/"\n  base_branch: "release/1.0"\n' > "$GPROJ/.specclaw/config.yaml"
  (cd "$GPROJ" && git branch -q "release/1.0")
  setup_json="$(cd "$GPROJ" && bash "$BUILD_BIN" setup .specclaw bb-test 2>/dev/null)"
  base_val="$(printf '%s' "$setup_json" | grep -o '"base_branch": "[^"]*"' | sed 's/.*: "//;s/"//')"
  assert_eq "7d config override wins" "release/1.0" "$base_val"

  # 7e (AC3) — no origin remote: falls back to local main/master without error
  NOREMOTE="$WORK/noremote-proj"
  mkdir -p "$NOREMOTE" && (
    cd "$NOREMOTE"
    git init -q -b main .
    git config user.email t@t && git config user.name t
    echo x > x.txt && git add . && git commit -qm x
    mkdir -p .specclaw/changes/nr-test
    printf 'version: 1\ngit:\n  strategy: "branch-per-change"\n  branch_prefix: "specclaw/"\n' > .specclaw/config.yaml
    printf '# t\n- [ ] `T1` — x\n  - Files: a\n' > .specclaw/changes/nr-test/tasks.md
  )
  setup_json="$(cd "$NOREMOTE" && bash "$BUILD_BIN" setup .specclaw nr-test 2>/dev/null)"
  base_val="$(printf '%s' "$setup_json" | grep -o '"base_branch": "[^"]*"' | sed 's/.*: "//;s/"//')"
  assert_eq "7e no-remote fallback" "main" "$base_val"

  # 7f (AC6) — specclaw-pr uses detected base, no hardcoded '--base main'
  if grep -q -- '--base "\$pr_base"' "$BIN_DIR/specclaw-pr" && ! grep -q -- '--base main' "$BIN_DIR/specclaw-pr"; then
    pass "7f pr --base uses detection"
  else
    fail "7f pr --base uses detection"
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
