#!/usr/bin/env bash
# run-status-row-tests.sh — regression suite for the status.md Progress-table row
# writer (bin/specclaw-status-row) and the two sed defects it replaces.
#
# The defects, both reproduced against the shipped templates/status.md:
#
#   D1: `sed -i "/^\|[[:space:]]*Verify[[:space:]]*\|/a| PR | … |"` — in a sed BRE
#       address `\|` is *alternation*, so the empty branch matched every line and
#       the PR row was appended after all 33 of them.
#   D2: `sed -i "s|^\(| *PR *|\).*|\1 ✅ Raised | $url |"` — the s command is
#       delimited by `|` while its pattern contains literal pipes, so sed refused
#       it outright: `sed: -e expression #1, char 14: unknown option to 's'`.
#       Non-zero under `set -euo pipefail` aborted specclaw-pr *after* the PR was
#       created, freezing every tracker at its pre-PR state.
#
# Plain bash + coreutils only. Run from anywhere:
#   bash plugins/specclaw/tests/run-status-row-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
TEMPLATE="$(cd "$SCRIPT_DIR/.." && pwd)/templates/status.md"

STATUS_ROW="$BIN_DIR/specclaw-status-row"
PR_SCRIPT="$BIN_DIR/specclaw-pr"
AZDO_PR_SCRIPT="$BIN_DIR/specclaw-azdo-pr"

for f in "$STATUS_ROW" "$TEMPLATE"; do
  if [[ ! -f "$f" ]]; then
    echo "FATAL: missing file: $f" >&2
    exit 2
  fi
done

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

URL="https://github.com/chan4lk/specclaw/pull/417"

# A status.md in the shipped template's shape, with the placeholders filled the
# way propose/verify leave them.
make_status() {
  local dest="$1"
  cat > "$dest" <<'EOF'
# Status: Multiple Owners per Objective

**Change:** objective-multi-owner
**Started:** 2026-07-30
**Last Updated:** 2026-07-30

## Progress

| Phase | Status | Notes |
|-------|--------|-------|
| Proposal | ✅ Approved | Operator resolved Q1/Q2/Q4 |
| Spec | ✅ Done | 14 FRs, 10 ACs |
| Design | ✅ Done | Shared permission service |
| Tasks | ✅ Done | 11 tasks / 4 waves |
| Build | ✅ Done | 11/11 tasks |
| Verify | ✅ Passed | All 10 ACs |

## Task Progress

**Completed:** 11 / 11
**Failed:** 0

## Issues

_None._
EOF
}

# ─── T1: the D1 regression — one PR row, not one per line ─────────────────────
S="$WORK/t1.md"
make_status "$S"
"$STATUS_ROW" "$S" "PR" "✅ Raised" "$URL" >/dev/null
assert_eq "T1a insert adds exactly one PR row" "1" "$(grep -c '^| PR |' "$S")"
assert_eq "T1b no stray rows outside the table" "0" \
  "$(grep -c '^| PR |' <<<"$(sed -n '1,9p' "$S")")"

# The old sed appended after *every* line of the file, header included.
assert_eq "T1c header line untouched" "# Status: Multiple Owners per Objective" \
  "$(head -1 "$S")"

# ─── T2: the row lands inside the Progress table, after the last row ──────────
S="$WORK/t2.md"
make_status "$S"
"$STATUS_ROW" "$S" "PR" "✅ Raised" "$URL" >/dev/null
assert_eq "T2a PR row follows the Verify row" "| Verify | ✅ Passed | All 10 ACs |" \
  "$(grep -B1 '^| PR |' "$S" | head -1)"
assert_eq "T2b PR row carries the URL" "| PR | ✅ Raised | $URL |" \
  "$(grep '^| PR |' "$S")"

# ─── T3: the D2 regression — updating an existing row must not error ──────────
S="$WORK/t3.md"
make_status "$S"
"$STATUS_ROW" "$S" "PR" "✅ Raised" "$URL" >/dev/null
NEW_URL="https://github.com/chan4lk/specclaw/pull/999"
if "$STATUS_ROW" "$S" "PR" "✅ Merged" "$NEW_URL" >/dev/null 2>"$WORK/t3.err"; then
  pass "T3a second write exits 0 (old sed exited 1 and killed specclaw-pr)"
else
  fail "T3a second write failed: $(cat "$WORK/t3.err")"
fi
assert_eq "T3b row replaced, not duplicated" "1" "$(grep -c '^| PR |' "$S")"
assert_eq "T3c row shows the new value" "| PR | ✅ Merged | $NEW_URL |" \
  "$(grep '^| PR |' "$S")"
assert_eq "T3d no sed error text leaked" "0" \
  "$(awk '/unknown option to/ { c++ } END { print c + 0 }' "$WORK/t3.err")"

# ─── T4: idempotence — same values twice is a byte-identical file ─────────────
S="$WORK/t4.md"
make_status "$S"
"$STATUS_ROW" "$S" "PR" "✅ Raised" "$URL" >/dev/null
cp "$S" "$WORK/t4.snapshot"
"$STATUS_ROW" "$S" "PR" "✅ Raised" "$URL" >/dev/null
if cmp -s "$S" "$WORK/t4.snapshot"; then
  pass "T4 re-running with identical values changes nothing"
else
  fail "T4 re-run mutated the file: $(diff "$WORK/t4.snapshot" "$S" | head -5)"
fi

# ─── T5: self-heal a file already corrupted by the D1 sed ─────────────────────
# 33 duplicate rows is what the stock template produced; collapse them to one.
S="$WORK/t5.md"
make_status "$S"
{
  for _ in $(seq 1 33); do echo "| PR | ✅ Raised | $URL |"; done
} >> "$S"
assert_eq "T5a fixture starts corrupted" "33" "$(grep -c '^| PR |' "$S")"
"$STATUS_ROW" "$S" "PR" "✅ Raised" "$URL" >/dev/null
assert_eq "T5b duplicates collapsed to one row" "1" "$(grep -c '^| PR |' "$S")"

# ─── T6: other rows are never touched ────────────────────────────────────────
S="$WORK/t6.md"
make_status "$S"
BEFORE="$(grep -c '^| ' "$S")"
"$STATUS_ROW" "$S" "PR" "✅ Raised" "$URL" >/dev/null
assert_eq "T6a exactly one row added" "$((BEFORE + 1))" "$(grep -c '^| ' "$S")"
assert_eq "T6b Build row intact" "| Build | ✅ Done | 11/11 tasks |" \
  "$(grep '^| Build |' "$S")"
assert_eq "T6c Verify row intact" "| Verify | ✅ Passed | All 10 ACs |" \
  "$(grep '^| Verify |' "$S")"

# ─── T7: a file with no Progress table falls back to a field line ────────────
S="$WORK/t7.md"
printf '# Status: bare\n\n**Change:** bare\n' > "$S"
"$STATUS_ROW" "$S" "PR" "✅ Raised" "$URL" >/dev/null
assert_eq "T7 falls back to a **PR:** line" "**PR:** $URL" "$(grep '^\*\*PR:\*\*' "$S")"

# ─── T8: notes containing regex/sed metacharacters survive ───────────────────
S="$WORK/t8.md"
make_status "$S"
ODD='https://ex.com/p/1?a=b&c=[x]|y\z'
"$STATUS_ROW" "$S" "PR" "✅ Raised" "$ODD" >/dev/null
assert_eq "T8a metacharacter note stored verbatim" "| PR | ✅ Raised | $ODD |" \
  "$(grep '^| PR |' "$S")"
assert_eq "T8b still exactly one PR row" "1" "$(grep -c '^| PR |' "$S")"

# ─── T9: the file is never truncated on a bad invocation ─────────────────────
S="$WORK/t9.md"
make_status "$S"
BYTES_BEFORE="$(wc -c < "$S")"
"$STATUS_ROW" "$WORK/does-not-exist.md" "PR" "✅ Raised" "$URL" >/dev/null 2>&1
RC=$?
assert_eq "T9a missing file exits 2" "2" "$RC"
assert_eq "T9b unrelated file untouched" "$BYTES_BEFORE" "$(wc -c < "$S")"

# ─── T10: the broken sed forms are gone from both PR scripts ─────────────────
# Guards against a re-introduction: `\|` in a sed address, or an `s|` whose
# pattern contains a literal pipe.
for script in "$PR_SCRIPT" "$AZDO_PR_SCRIPT"; do
  name="$(basename "$script")"
  [[ -f "$script" ]] || { fail "T10 $name missing"; continue; }
  if grep -qE 'sed_i "/\^\\\|' "$script"; then
    fail "T10 $name still has a sed address starting with \\| (D1)"
  else
    pass "T10 $name has no \\|-addressed sed (D1 fixed)"
  fi
  if grep -qE 'sed_i "s\|\^\\\(\|' "$script"; then
    fail "T10 $name still has the s| pattern with literal pipes (D2)"
  else
    pass "T10 $name has no pipe-delimited s| over table rows (D2 fixed)"
  fi
done

# ─── T11: post-PR bookkeeping cannot abort the script ────────────────────────
# save_pr_url runs after `gh pr create` / the ADO POST; an unguarded non-zero
# there aborts under `set -e` and freezes the trackers while the PR is already live.
for script in "$PR_SCRIPT" "$AZDO_PR_SCRIPT"; do
  name="$(basename "$script")"
  [[ -f "$script" ]] || continue
  if grep -qE '^[[:space:]]*save_pr_url "\$pr_url"[[:space:]]*$' "$script"; then
    fail "T11 $name calls save_pr_url unguarded (an abort here freezes trackers)"
  else
    pass "T11 $name guards the save_pr_url call"
  fi
done

echo
echo "─────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
