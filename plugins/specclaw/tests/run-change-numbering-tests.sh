#!/usr/bin/env bash
# run-change-numbering-tests.sh — regression suite for numbered change folders:
# `bin/specclaw-next-change-number`, `bin/specclaw-renumber-changes`, and the
# `ordered_dir_names()` ordering shared by `specclaw-update-status` and
# `specclaw-reconcile`.
#
# What this pins:
#
#   next-change-number
#     AC1   an empty changes/ prints 001
#     AC2   001-a + archive/007-b prints 008 — the archive is scanned, gaps stay
#     AC3   only unnumbered folders prints 001, exit 0
#     AC4   008-a prints 009 and 009-a prints 010 — THE OCTAL TRAP. `$((08))` is
#           a bash *syntax error*, not a zero, so an unguarded script aborts on
#           the eighth change of every repo. The single most likely defect here.
#     AC5   999-a prints 1000 — `%03d` is a minimum width, not a truncation
#     AC6   `archive` and `archive-cleanup` are both handled, exit 0
#     AC6a  archive/2026-07-22-build-engine alone prints 001 — the legacy date
#           prefix is a *year*, not an ordinal (FR5a). Read as one, this repo's
#           26 archives would make the next proposal `2027-<slug>` forever.
#     AC6b  2026-some-slug prints 2027 — the FR5a exclusion fires only on the
#           full YYYY-MM-DD shape, never on any leading four-digit run
#     plus   no changes/ at all, no archive/, and a *file* named `020-notadir`
#
#   renumber-changes
#     AC7   dry run prints the whole plan and leaves the tree byte-identical
#     AC8   --apply orders by Created: date, not by folder name
#     AC9   no `Created:` line → git first-commit date; no proposal.md at all →
#           sorts last; neither crashes the run
#     AC10  a shared date breaks ties by name, identically on repeated runs
#     AC11  an already-numbered folder refuses (and a `2026-07-22-` legacy one
#           does NOT trip it, FR5a); --force --apply renumbers from 001
#     AC12  a planned target that already exists aborts before the first rename
#     AC13/FR15a  an active folder's state.json keeps `verdict`/`url`/`tasks`/
#           `branch`/`at` byte-for-byte across the rename. set-phase rebuilds
#           the record from its arguments, so a dropped field silently *deletes*
#           a PASS verdict — this is the assertion that catches it.
#     FR15b an archived folder is renamed and its state.json left untouched
#     FR12  a checked-out branch / live worktree refuses
#     E9    a name full of shell metacharacters survives
#     E10   a folder with no state.json is skipped, not failed
#
#   ordering
#     AC17  010-a, 002-b, unnumbered-c list as 002-b, 010-a, unnumbered-c —
#           numeric, not lexical, unnumbered last; a legacy date-prefixed folder
#           sorts with the unnumbered group
#     AC18  the hint line carries its count when unnumbered folders exist and is
#           completely absent at zero
#     plus  the two copies of `ordered_dir_names()` are byte-identical
#
# Plain bash + coreutils, plus python3 for the JSON assertions — no jq, per
# plugins/specclaw/CLAUDE.md. Every fixture lives under one temp dir removed on
# exit; the repository's own .specclaw is only ever read, never written. Run
# from anywhere:
#   bash plugins/specclaw/tests/run-change-numbering-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

NEXT_NUM="$BIN_DIR/specclaw-next-change-number"
RENUMBER="$BIN_DIR/specclaw-renumber-changes"
SET_PHASE="$BIN_DIR/specclaw-set-phase"
USTATUS="$BIN_DIR/specclaw-update-status"
RECONCILE="$BIN_DIR/specclaw-reconcile"

for f in "$NEXT_NUM" "$RENUMBER" "$SET_PHASE" "$USTATUS" "$RECONCILE"; do
  if [[ ! -f "$f" ]]; then
    echo "FATAL: missing file: $f" >&2
    exit 2
  fi
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: this suite needs python3 to read the JSON it asserts on" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "FATAL: this suite needs git for the FR12 and AC9 fixtures" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Every non-git fixture must look like it is *outside* a working tree, so the
# renames take the plain-`mv` path (FR14, edge case 11) and the FR12 mid-build
# check has nothing to inspect. Without a ceiling, a $TMPDIR that happened to sit
# inside someone's repo would silently change which branch the suite tests.
export GIT_CEILING_DIRECTORIES="$WORK"

# One case runs the real script against this repository's own .specclaw (AC6a).
# Snapshot its working-tree status now so the last assertion can prove that read
# stayed a read. The ceiling above does not reach here — $WORK is not an ancestor
# of the checkout — so these `git` calls resolve normally.
REPO_IS_GIT=0
REPO_SPECCLAW_BEFORE=""
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_IS_GIT=1
  REPO_SPECCLAW_BEFORE="$(git -C "$REPO_ROOT" status --porcelain -- .specclaw 2>/dev/null || true)"
fi

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

assert_ne() {
  local label="$1" forbidden="$2" actual="$3"
  if [[ "$actual" != "$forbidden" ]]; then
    pass "$label (not '$forbidden')"
  else
    fail "$label — value should not be '$forbidden', but is"
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

assert_dir() {
  local label="$1" dir="$2"
  if [[ -d "$dir" ]]; then
    pass "$label"
  else
    fail "$label — no such directory: $dir"
  fi
}

assert_no_dir() {
  local label="$1" dir="$2"
  if [[ ! -d "$dir" ]]; then
    pass "$label"
  else
    fail "$label — directory should be gone: $dir"
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
OUT=""
ERR=""
# run <cmd…> — capture rc, stdout and stderr separately; never abort the suite.
run() {
  RC=0
  "$@" >"$WORK/last.out" 2>"$WORK/last.err" || RC=$?
  OUT="$(cat "$WORK/last.out")"
  ERR="$(cat "$WORK/last.err")"
}

# json_get <file> <dotted.path> — python3 only. jq is banned in the suites
# (plugins/specclaw/CLAUDE.md), and pinning one reader also makes the byte
# comparisons below deterministic. Any failure prints nothing.
json_get() {
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
' "$1" "$2" 2>/dev/null || true
}

json_ok() {
  python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1
}

# spec_dir <name> — a fresh, empty .specclaw fixture. One directory per case, so
# no case can see another's folders.
spec_dir() {
  local d="$WORK/$1/.specclaw"
  mkdir -p "$d/changes"
  printf '%s' "$d"
}

# mkchange <specclaw_dir> <relative_name> [created_date] — a change folder, with
# a proposal.md carrying a `**Created:**` line when a date is given.
mkchange() {
  local spec="$1" rel="$2" created="${3:-}"
  mkdir -p "${spec}/changes/${rel}"
  if [ -n "$created" ]; then
    printf '# Proposal: %s\n\n**Created:** %s\n' "${rel##*/}" "$created" \
      >"${spec}/changes/${rel}/proposal.md"
  fi
}

# make_tasks <file> <done> <total> — the checkbox markers update-status counts.
make_tasks() {
  local f="$1" nd="$2" nt="$3" i n=1
  printf '# Tasks\n\n' >"$f"
  for ((i = 0; i < nd; i++)); do
    printf -- '- [x] T%d — done\n' "$n" >>"$f"
    n=$((n + 1))
  done
  while [ "$n" -le "$nt" ]; do
    printf -- '- [ ] T%d — pending\n' "$n" >>"$f"
    n=$((n + 1))
  done
}

# snapshot <dir> — names plus per-file checksums, sorted. "Byte-identical tree"
# in the AC7 and AC12 sense: no path added, removed or rewritten.
snapshot() {
  (
    cd "$1" 2>/dev/null || return 0
    find . | LC_ALL=C sort
    find . -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort
  )
}

# names_in <dir> — the immediate subdirectory names, one per line, C-collated.
names_in() {
  (
    cd "$1" 2>/dev/null || return 0
    find . -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort | tr '\n' ' '
  )
}

# init_repo <path> — a throwaway git repo with *local* identity, so the suite
# never depends on (or is broken by) the ambient git config.
init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -c init.defaultBranch=main init -q "$repo"
  git -C "$repo" config user.email "tests@specclaw.invalid"
  git -C "$repo" config user.name "specclaw tests"
  git -C "$repo" config commit.gpgsign false
}

# commit_all <repo> <message> [iso_date]
commit_all() {
  local repo="$1" msg="$2" when="${3:-}"
  git -C "$repo" add -A
  if [ -n "$when" ]; then
    GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" \
      git -C "$repo" commit -q -m "$msg"
  else
    git -C "$repo" commit -q -m "$msg"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# specclaw-next-change-number
# ═════════════════════════════════════════════════════════════════════════════

# ─── AC1: an empty changes/ ──────────────────────────────────────────────────
S="$(spec_dir ac1)"
run "$NEXT_NUM" "$S"
assert_eq "AC1a exits 0" "0" "$RC"
assert_eq "AC1b an empty changes/ prints 001" "001" "$OUT"
assert_eq "AC1c and says nothing on stderr" "" "$ERR"

# ─── AC2: the archive is scanned and gaps are preserved ──────────────────────
S="$(spec_dir ac2)"
mkchange "$S" "001-a"
mkchange "$S" "archive/007-b"
run "$NEXT_NUM" "$S"
assert_eq "AC2a exits 0" "0" "$RC"
assert_eq "AC2b max+1 across changes/ and archive/, gap preserved" "008" "$OUT"

# ─── AC3: only unnumbered folders ────────────────────────────────────────────
S="$(spec_dir ac3)"
mkchange "$S" "alpha"
mkchange "$S" "beta-gamma"
mkchange "$S" "archive/old-thing"
run "$NEXT_NUM" "$S"
assert_eq "AC3a unnumbered folders are not an error" "0" "$RC"
assert_eq "AC3b they contribute nothing to the maximum" "001" "$OUT"

# ─── AC4: the octal trap ─────────────────────────────────────────────────────
# `008` and `009` are the only two leading-zero values bash rejects outright:
# `$((08))` is "value too great for base", a syntax error that aborts the script
# rather than mis-sorting. Both are pinned, and stderr is asserted empty because
# that is where the trap announces itself.
S="$(spec_dir ac4a)"
mkchange "$S" "008-a"
run "$NEXT_NUM" "$S"
assert_eq "AC4a 008-a exits 0 (no octal abort)" "0" "$RC"
assert_eq "AC4b 008-a prints 009" "009" "$OUT"
assert_eq "AC4c nothing on stderr — an octal error would land here" "" "$ERR"

S="$(spec_dir ac4b)"
mkchange "$S" "009-a"
run "$NEXT_NUM" "$S"
assert_eq "AC4d 009-a exits 0" "0" "$RC"
assert_eq "AC4e 009-a prints 010" "010" "$OUT"
assert_eq "AC4f nothing on stderr" "" "$ERR"

# The rest of the leading-zero range, swept in one fixture apiece so a partial
# `10#` fix cannot pass by covering only the two values bash rejects.
for n in 001 002 003 004 005 006 007; do
  S="$(spec_dir "ac4-$n")"
  mkchange "$S" "${n}-a"
  run "$NEXT_NUM" "$S"
  assert_eq "AC4g ${n}-a → $(printf '%03d' "$((10#$n + 1))")" \
    "$(printf '%03d' "$((10#$n + 1))")" "$OUT"
done

# ─── AC5: widening past 999 ──────────────────────────────────────────────────
S="$(spec_dir ac5)"
mkchange "$S" "999-a"
run "$NEXT_NUM" "$S"
assert_eq "AC5a exits 0" "0" "$RC"
assert_eq "AC5b %03d is a minimum width, so 1000 widens" "1000" "$OUT"

# ─── AC6: `archive` vs `archive-cleanup` ─────────────────────────────────────
S="$(spec_dir ac6)"
mkdir -p "$S/changes/archive"
mkchange "$S" "archive-cleanup"
run "$NEXT_NUM" "$S"
assert_eq "AC6a the reserved container and a lookalike both exit 0" "0" "$RC"
assert_eq "AC6b neither counts as a numbered change" "001" "$OUT"

S="$(spec_dir ac6b)"
mkchange "$S" "archive/004-x"
mkchange "$S" "archive-cleanup"
run "$NEXT_NUM" "$S"
assert_eq "AC6c archive-cleanup stays an ordinary unnumbered change" "005" "$OUT"

# ─── AC6a: the legacy YYYY-MM-DD- prefix is a year, not an ordinal ───────────
S="$(spec_dir ac6a)"
mkchange "$S" "archive/2026-07-22-build-engine"
run "$NEXT_NUM" "$S"
assert_eq "AC6a-1 exits 0" "0" "$RC"
assert_eq "AC6a-2 a legacy archive prefix yields 001, never 2027" "001" "$OUT"

# The same rule on the active side, and with a real ordinal alongside it: the
# legacy folder must not raise the maximum past the genuine 003.
S="$(spec_dir ac6a2)"
mkchange "$S" "2026-07-22-legacy"
mkchange "$S" "003-real"
mkchange "$S" "archive/2026-07-22-another"
run "$NEXT_NUM" "$S"
assert_eq "AC6a-3 a legacy prefix beside a real ordinal does not win" "004" "$OUT"

# ─── AC6b: the exclusion is narrow, not "any four-digit run" ─────────────────
S="$(spec_dir ac6bb)"
mkchange "$S" "2026-some-slug"
run "$NEXT_NUM" "$S"
assert_eq "AC6b-1 exits 0" "0" "$RC"
assert_eq "AC6b-2 a genuine four-digit ordinal still counts" "2027" "$OUT"

# `2026-07-something` is not the full date shape either — only YYYY-MM-DD is.
S="$(spec_dir ac6bc)"
mkchange "$S" "2026-07-partial"
run "$NEXT_NUM" "$S"
assert_eq "AC6b-3 a partial date is not the excluded shape" "2027" "$OUT"

# ─── Edge cases 1, 2 and a non-directory ─────────────────────────────────────
NOCHANGES="$WORK/nochanges/.specclaw"
mkdir -p "$NOCHANGES"
run "$NEXT_NUM" "$NOCHANGES"
assert_eq "E1a no changes/ directory at all exits 0" "0" "$RC"
assert_eq "E1b and prints 001" "001" "$OUT"

S="$(spec_dir noarchive)"
mkchange "$S" "003-a"
run "$NEXT_NUM" "$S"
assert_eq "E2a an absent archive/ is skipped silently" "0" "$RC"
assert_eq "E2b and does not disturb the maximum" "004" "$OUT"

S="$(spec_dir notadir)"
mkchange "$S" "002-a"
: >"$S/changes/020-notadir"
run "$NEXT_NUM" "$S"
assert_eq "E3a a *file* named 020-notadir is ignored" "003" "$OUT"
assert_eq "E3b and is not an error" "0" "$RC"

# ─── Usage ───────────────────────────────────────────────────────────────────
run "$NEXT_NUM"
assert_eq "Ua no argument prints usage and exits 0" "0" "$RC"
assert_contains "Ub the usage names the script" "specclaw-next-change-number" "$OUT"
run "$NEXT_NUM" "$WORK/does-not-exist"
assert_eq "Uc a missing specclaw dir exits 2" "2" "$RC"
assert_contains "Ud with a message naming it" "no such specclaw dir" "$ERR"

# ─── AC6a against this repository's real .specclaw (read-only) ───────────────
# The exact value moves with the repo, so only the invariant AC6a exists to
# protect is asserted: never 2027, and never a four-digit answer derived from a
# legacy archive year. Read-only — nothing here writes to the repo's .specclaw.
if [ -d "${REPO_ROOT}/.specclaw/changes" ]; then
  run "$NEXT_NUM" "${REPO_ROOT}/.specclaw"
  assert_eq "AC6a-4 the real .specclaw resolves cleanly" "0" "$RC"
  assert_ne "AC6a-5 and never yields 2027 (FR5a on 26 legacy archives)" "2027" "$OUT"
  # `{3,}` rather than exactly three digits: FR2 widens past 999 instead of
  # truncating, so pinning the length to three would turn correct behaviour into
  # a CI failure the moment this repo passes 99 numbered changes. The year-vs-
  # ordinal invariant this case exists for is carried by AC6a-5 above.
  if [[ "$OUT" =~ ^[0-9]{3,}$ ]]; then
    pass "AC6a-6 the real answer is a zero-padded ordinal (= '$OUT')"
  else
    fail "AC6a-6 the real answer looks derived from a year, not an ordinal: '$OUT'"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# specclaw-renumber-changes
# ═════════════════════════════════════════════════════════════════════════════

# ─── AC7 / AC8: dry run then apply, ordered by date rather than name ─────────
# The three `Created:` dates are deliberately the reverse of alphabetical order,
# so a name-ordered implementation produces a different answer than a
# date-ordered one and cannot pass by accident.
S="$(spec_dir plan)"
mkchange "$S" "zeta" "2026-01-05"
mkchange "$S" "mid" "2026-02-02"
mkchange "$S" "alpha" "2026-03-03"
BEFORE="$(snapshot "$S")"

run "$RENUMBER" "$S"
assert_eq "AC7a a dry run exits 0" "0" "$RC"
assert_contains "AC7b the plan names the first rename" "changes/zeta → changes/001-zeta" "$OUT"
assert_contains "AC7c and the second" "changes/mid → changes/002-mid" "$OUT"
assert_contains "AC7d and the third" "changes/alpha → changes/003-alpha" "$OUT"
assert_contains "AC7e it says it is a dry run" "Dry run: 3 change folder(s) planned, 3 rename(s)." "$OUT"
assert_contains "AC7f and that nothing moved" "Nothing was modified." "$OUT"
assert_contains "AC7g and how to apply it" "--apply" "$OUT"
assert_eq "AC7h the tree is byte-identical after the dry run" "$BEFORE" "$(snapshot "$S")"

run "$RENUMBER" "$S" --apply
assert_eq "AC8a --apply exits 0" "0" "$RC"
assert_eq "AC8b the result is date order, not name order" \
  "001-zeta 002-mid 003-alpha " "$(names_in "$S/changes")"
assert_contains "AC8c and it reports what it did" "Renumbered 3 of 3 change folder(s)." "$OUT"
assert_no_dir "AC8d no old name survives" "$S/changes/zeta"

# Re-applying is a no-op: slug_of strips the ordinal, so the plan converges.
run "$RENUMBER" "$S" --force --apply
assert_eq "AC8e a second --force --apply exits 0" "0" "$RC"
assert_contains "AC8f and renames nothing" "Renumbered 0 of 3 change folder(s)." "$OUT"
assert_eq "AC8g the names are unchanged" "001-zeta 002-mid 003-alpha " "$(names_in "$S/changes")"

# ─── "nothing to renumber" ───────────────────────────────────────────────────
S="$(spec_dir empty)"
run "$RENUMBER" "$S"
assert_eq "AC7i an empty changes/ exits 0" "0" "$RC"
assert_contains "AC7j and says there is nothing to do" "nothing to renumber" "$OUT"

# ─── AC9: the git fallback, and a folder with no proposal.md at all ──────────
# Three date sources in one fixture:
#   hasdate   — a `**Created:**` line          (precedence 1) 2026-01-01
#   gitdated  — a proposal.md with no Created: (precedence 2) 2026-02-02, from
#               the commit that first added it
#   orphan    — no proposal.md and never committed → no date at all, sorts last
# `orphan` is also untracked, so `git mv` fails on it and the run must fall back
# to plain `mv` (FR14) rather than abort.
REPO9="$WORK/gitac9"
init_repo "$REPO9"
S="$REPO9/.specclaw"
mkdir -p "$S/changes"
mkchange "$S" "hasdate" "2026-01-01"
commit_all "$REPO9" "add hasdate" "2026-01-01T12:00:00 +0000"
mkdir -p "$S/changes/gitdated"
printf '# Proposal: gitdated\n\nNo created line here at all.\n' >"$S/changes/gitdated/proposal.md"
commit_all "$REPO9" "add gitdated" "2026-02-02T12:00:00 +0000"
mkdir -p "$S/changes/orphan"

run "$RENUMBER" "$S"
assert_eq "AC9a a proposal with no Created: does not crash the plan" "0" "$RC"
assert_contains "AC9b the Created: folder sorts first" "changes/hasdate → changes/001-hasdate" "$OUT"
assert_contains "AC9c the git-dated folder sorts second" "changes/gitdated → changes/002-gitdated" "$OUT"
assert_contains "AC9d the folder with no proposal.md sorts last" "changes/orphan → changes/003-orphan" "$OUT"

run "$RENUMBER" "$S" --apply
assert_eq "AC9e --apply exits 0 despite the untracked folder" "0" "$RC"
assert_eq "AC9f the order held through the rename" "001-hasdate 002-gitdated 003-orphan " \
  "$(names_in "$S/changes")"
assert_contains "AC9g git mv failing on an untracked folder falls back to mv (FR14)" \
  "git mv failed for changes/orphan" "$ERR"
assert_contains "AC9h and the tracked folders went through git mv" \
  ".specclaw/changes/001-hasdate/proposal.md" "$(git -C "$REPO9" ls-files)"
assert_lacks "AC9i with the old path dropped from the index" \
  ".specclaw/changes/hasdate/proposal.md" "$(git -C "$REPO9" ls-files)"

# ─── AC10: a shared date breaks ties by name, repeatably ─────────────────────
# Built twice into two independent fixtures and compared, so the assertion is
# about determinism rather than about one lucky readdir order.
for tag in tie1 tie2; do
  S="$(spec_dir "$tag")"
  mkchange "$S" "bravo" "2026-04-04"
  mkchange "$S" "alpha" "2026-04-04"
  mkchange "$S" "charlie" "2026-05-05"
  run "$RENUMBER" "$S" --apply
  assert_eq "AC10a ($tag) exits 0" "0" "$RC"
done
TIE1="$(names_in "$WORK/tie1/.specclaw/changes")"
TIE2="$(names_in "$WORK/tie2/.specclaw/changes")"
assert_eq "AC10b the tie breaks by name" "001-alpha 002-bravo 003-charlie " "$TIE1"
assert_eq "AC10c and identically on a repeated run" "$TIE1" "$TIE2"

# ─── AC11 / FR5a: already numbered refuses; a legacy folder does not ─────────
# The legacy `2026-07-22-legacy` folder is the whole point of this case: read as
# numbered it would make the tool refuse on the one repo it exists to migrate.
S="$(spec_dir already)"
mkchange "$S" "005-numbered" "2026-01-01"
mkchange "$S" "2026-07-22-legacy"
mkchange "$S" "plainfolder" "2026-02-02"
BEFORE="$(snapshot "$S")"

run "$RENUMBER" "$S" --apply
assert_eq "AC11a an already-numbered folder exits non-zero" "3" "$RC"
assert_contains "AC11b with an explanatory refusal" "refusing to run" "$ERR"
assert_contains "AC11c naming exactly one offender" "1 change folder(s) are already numbered" "$ERR"
assert_contains "AC11d and its parsed number" "005-numbered (number 5)" "$ERR"
assert_lacks "AC11e the legacy YYYY-MM-DD- folder is NOT counted as numbered (FR5a)" \
  "2026-07-22-legacy" "$ERR"
assert_contains "AC11f the message points at --force" "--force" "$ERR"
assert_eq "AC11g and nothing was renamed" "$BEFORE" "$(snapshot "$S")"

run "$RENUMBER" "$S" --force --apply
assert_eq "AC11h --force --apply exits 0" "0" "$RC"
assert_eq "AC11i every folder is renumbered from 001 in date order" \
  "001-numbered 002-plainfolder 003-legacy " "$(names_in "$S/changes")"
assert_no_dir "AC11j the legacy date prefix is stripped, not carried (edge 7)" \
  "$S/changes/003-2026-07-22-legacy"
assert_no_dir "AC11k and the old numbered name is gone" "$S/changes/005-numbered"

# ─── AC12: a planned target that already exists aborts before any rename ─────
# The collision is a plain *file*, which `collect` never sees (it globs
# directories only) — so FR11 does not fire first and FR13 is what stops the run.
S="$(spec_dir collide)"
mkchange "$S" "beta" "2026-01-01"
mkchange "$S" "gamma" "2026-02-02"
: >"$S/changes/001-beta"
BEFORE="$(snapshot "$S")"

run "$RENUMBER" "$S" --apply
assert_eq "AC12a a collision exits non-zero" "5" "$RC"
assert_contains "AC12b before the first rename" "aborting before any rename" "$ERR"
assert_contains "AC12c naming the conflicting target" \
  "changes/beta → changes/001-beta (target exists)" "$ERR"
assert_contains "AC12d and saying so plainly" "Nothing has been moved." "$ERR"
assert_eq "AC12e the tree is byte-identical" "$BEFORE" "$(snapshot "$S")"
assert_dir "AC12f the *second* folder was not moved either" "$S/changes/gamma"

# ─── AC13 / FR15a: the state.json round-trip on an active folder ─────────────
# set-phase rebuilds a phase record from its arguments, so any field the refresh
# forgets to pass through is *deleted*. A verified change would silently lose its
# PASS verdict and gain a fresh `at`. Every field is asserted, and then the whole
# record line is compared byte-for-byte — which is also the exact condition under
# which set-phase preserves the original timestamp.
S="$(spec_dir active)"
mkchange "$S" "mychange" "2026-03-01"
PIPE_URL='https://ex.com/p/1?a=b|c=[d]&e'
# The status arguments are quoted so `done` reads as a literal rather than as a
# loop keyword — to bash it is one either way, but the quoting keeps shellcheck
# from flagging SC1010 on a line that is perfectly correct.
run "$SET_PHASE" "$S" mychange build "done" --tasks 5/9/1 --branch claude/mychange
assert_eq "AC13a fixture: build recorded" "0" "$RC"
run "$SET_PHASE" "$S" mychange verify "passed" --verdict PASS --url "$PIPE_URL" --tasks 5/9/1
assert_eq "AC13b fixture: verify recorded" "0" "$RC"

OLD_STATE="$S/changes/mychange/state.json"
cp "$OLD_STATE" "$WORK/ac13.before.json"
OLD_AT="$(json_get "$OLD_STATE" phases.verify.at)"
OLD_VERIFY_LINE="$(grep '"verify":' "$OLD_STATE")"
OLD_BUILD_LINE="$(grep '"build":' "$OLD_STATE")"
cp "$S/changes/mychange/status.md" "$WORK/ac13.status.before.md"

run "$RENUMBER" "$S" --apply
assert_eq "AC13c --apply exits 0" "0" "$RC"
NEW="$S/changes/001-mychange"
assert_dir "AC13d the folder was renamed" "$NEW"
assert_no_dir "AC13e and the old path is gone" "$S/changes/mychange"

if json_ok "$NEW/state.json"; then
  pass "AC13f state.json still parses as JSON"
else
  fail "AC13f state.json no longer parses: $(cat "$NEW/state.json")"
fi
assert_eq "AC13g the change field names the new folder" "001-mychange" \
  "$(json_get "$NEW/state.json" change)"
assert_eq "AC13h the phase is unchanged" "verify" "$(json_get "$NEW/state.json" phase)"
assert_eq "AC13i the status is unchanged" "passed" \
  "$(json_get "$NEW/state.json" phases.verify.status)"
assert_eq "AC13j/FR15a the PASS verdict survived" "PASS" \
  "$(json_get "$NEW/state.json" phases.verify.verdict)"
assert_eq "AC13k/FR15a the url survived, pipes and all" "$PIPE_URL" \
  "$(json_get "$NEW/state.json" phases.verify.url)"
assert_eq "AC13l/FR15a the task counts survived" '{"done":5,"total":9,"failed":1}' \
  "$(json_get "$NEW/state.json" phases.verify.tasks)"
assert_eq "AC13m/FR15a the branch survived" "claude/mychange" \
  "$(json_get "$NEW/state.json" branch)"
assert_eq "AC13n/FR15a the at timestamp was preserved, not restamped" "$OLD_AT" \
  "$(json_get "$NEW/state.json" phases.verify.at)"
assert_eq "AC13o/FR15a the whole verify record is byte-identical" "$OLD_VERIFY_LINE" \
  "$(grep '"verify":' "$NEW/state.json")"
assert_eq "AC13p the earlier build record is byte-identical too" "$OLD_BUILD_LINE" \
  "$(grep '"build":' "$NEW/state.json")"
assert_same_file "AC13q status.md was not disturbed by the refresh" \
  "$WORK/ac13.status.before.md" "$NEW/status.md"
# The strongest form of "otherwise unchanged": exactly one line of the file
# moved, and it is the `change` field. Two diff markers, one `<` and one `>`.
assert_eq "AC13r exactly one line of state.json differs from before the rename" "2" \
  "$(diff "$WORK/ac13.before.json" "$NEW/state.json" | grep -c '^[<>]')"
assert_eq "AC13s and that line is the change field" "2" \
  "$(diff "$WORK/ac13.before.json" "$NEW/state.json" | grep -c '^[<>].*"change"')"

# ─── FR15b: an archived folder is renamed, its state.json left untouched ─────
# set-phase resolves `<specclaw_dir>/changes/<change>`, so refreshing an archived
# folder would record `"change": "archive/001-…"` — a path, not an identity.
# Archived state is terminal and read by nothing, so it is skipped entirely.
S="$(spec_dir archived)"
mkchange "$S" "archive/oldname" "2026-01-01"
cat >"$S/changes/archive/oldname/state.json" <<'EOF'
{
  "change": "oldname",
  "phase": "archived",
  "branch": "claude/oldname",
  "phases": {
    "verify": {"status":"passed","at":"2026-01-02T03:04:05Z","verdict":"PASS"},
    "archived": {"status":"done","at":"2026-01-03T03:04:05Z"}
  }
}
EOF
cp "$S/changes/archive/oldname/state.json" "$WORK/fr15b.before.json"

run "$RENUMBER" "$S" --apply
assert_eq "FR15b-a --apply exits 0" "0" "$RC"
assert_dir "FR15b-b the archived folder was renamed" "$S/changes/archive/001-oldname"
assert_contains "FR15b-c and reported under its archive path" \
  "changes/archive/oldname → changes/archive/001-oldname" "$OUT"
assert_same_file "FR15b-d its state.json is byte-identical — never refreshed" \
  "$WORK/fr15b.before.json" "$S/changes/archive/001-oldname/state.json"
assert_eq "FR15b-e so the change field still holds the pre-rename name" "oldname" \
  "$(json_get "$S/changes/archive/001-oldname/state.json" change)"
assert_lacks "FR15b-f and no 'archive/...' path was ever written as an identity" \
  "archive/" "$(json_get "$S/changes/archive/001-oldname/state.json" change)"

# ─── FR12: a checked-out branch or live worktree refuses ─────────────────────
# The refusal is a *validate* step, so it fires on the dry run too — a plan that
# a user could act on is itself unsafe while a build holds the old path.
REPO12="$WORK/gitbusy"
init_repo "$REPO12"
S="$REPO12/.specclaw"
mkdir -p "$S/changes"
mkchange "$S" "gamma-delta" "2026-01-01"
commit_all "$REPO12" "add gamma-delta"
git -C "$REPO12" checkout -q -b "specclaw/gamma-delta"
BEFORE="$(snapshot "$S")"

run "$RENUMBER" "$S"
assert_eq "FR12a a checked-out branch refuses even the dry run" "4" "$RC"
assert_contains "FR12b naming the change" "1 change(s) look mid-build" "$ERR"
assert_contains "FR12c and the branch it is checked out on" \
  "gamma-delta (checked-out branch specclaw/gamma-delta)" "$ERR"
assert_contains "FR12d with the reason" "still references the old folder path" "$ERR"

run "$RENUMBER" "$S" --apply
assert_eq "FR12e --apply refuses identically" "4" "$RC"
assert_eq "FR12f and moved nothing" "$BEFORE" "$(snapshot "$S")"

# Back on a branch that names nothing, the same fixture proceeds — proving the
# refusal was about the branch, not about the repo being a git working tree.
git -C "$REPO12" checkout -q main
run "$RENUMBER" "$S" --apply
assert_eq "FR12g off that branch the same fixture applies cleanly" "0" "$RC"
assert_dir "FR12h and the rename happened" "$S/changes/001-gamma-delta"

# A live worktree for a change is the other half of FR12. specclaw creates them
# at `.specclaw/worktrees/<change>`, so the path's last segment IS the change
# name — that is what the refusal keys on.
REPO12B="$WORK/gitwt"
init_repo "$REPO12B"
S="$REPO12B/.specclaw"
mkdir -p "$S/changes"
mkchange "$S" "sidebranch-work" "2026-01-01"
commit_all "$REPO12B" "add sidebranch-work"
git -C "$REPO12B" worktree add -q -b wt-topic "$WORK/worktrees/sidebranch-work" >/dev/null 2>&1
run "$RENUMBER" "$S"
assert_eq "FR12i a live worktree naming the change refuses" "4" "$RC"
assert_contains "FR12j and says which" "sidebranch-work" "$ERR"

# ...and the matching is on whole path segments, not a substring. A worktree at
# `wt-sidebranch-work` merely *contains* the change name; it is not that
# change's worktree, and refusing on it would block a backfill that was safe.
# The same asymmetry applies to branches: `specclaw/foo-bar` does not name the
# change `foo`. On a repo whose changes share name stems, a substring test
# refuses on most of them.
REPO12C="$WORK/gitwt-near"
init_repo "$REPO12C"
S="$REPO12C/.specclaw"
mkdir -p "$S/changes"
mkchange "$S" "sidebranch" "2026-01-01"
commit_all "$REPO12C" "add sidebranch"
git -C "$REPO12C" worktree add -q -b wt-topic "$WORK/worktrees/wt-sidebranch-work" >/dev/null 2>&1
git -C "$REPO12C" checkout -q -b "specclaw/sidebranch-work"
run "$RENUMBER" "$S"
assert_eq "FR12k a near-miss worktree and branch do not refuse" "0" "$RC"
assert_contains "FR12l and the plan is produced" "001-sidebranch" "$OUT"

# ─── Edge 9: a name full of shell and regex metacharacters ───────────────────
S="$(spec_dir meta)"
ODD='weird [x]*name&thing'
mkchange "$S" "$ODD" "2026-01-01"
mkchange "$S" "normal" "2026-02-02"

run "$RENUMBER" "$S"
assert_eq "E9a a metacharacter name plans cleanly" "0" "$RC"
assert_contains "E9b and appears verbatim in the plan" "changes/${ODD} → changes/001-${ODD}" "$OUT"

run "$RENUMBER" "$S" --apply
assert_eq "E9c --apply exits 0" "0" "$RC"
assert_dir "E9d the folder was renamed with its metacharacters intact" "$S/changes/001-${ODD}"
assert_no_dir "E9e and the old path is gone" "$S/changes/${ODD}"
assert_dir "E9f the ordinary folder alongside it is unaffected" "$S/changes/002-normal"

# ─── Edge 10: a folder with no state.json is skipped, not failed ─────────────
S="$(spec_dir nostate)"
mkchange "$S" "nostate" "2026-01-01"
run "$RENUMBER" "$S" --apply
assert_eq "E10a a folder with no state.json exits 0" "0" "$RC"
assert_dir "E10b and is renamed" "$S/changes/001-nostate"
if [[ -f "$S/changes/001-nostate/state.json" ]]; then
  fail "E10c the refresh must be skipped, not backfilled"
else
  pass "E10c no state.json was invented for it"
fi
assert_lacks "E10d and no warning was raised about it" "state.json" "$ERR"

# ─── Usage ───────────────────────────────────────────────────────────────────
run "$RENUMBER"
assert_eq "Re-a no argument prints usage and exits 0" "0" "$RC"
assert_contains "Re-b naming the script" "specclaw-renumber-changes" "$OUT"
run "$RENUMBER" "$WORK/does-not-exist"
assert_eq "Re-c a missing specclaw dir exits 2" "2" "$RC"
run "$RENUMBER" "$(spec_dir badopt)" --nope
assert_eq "Re-d an unknown option exits 2" "2" "$RC"
assert_contains "Re-e naming the option" "unknown option: --nope" "$ERR"

# ═════════════════════════════════════════════════════════════════════════════
# Ordering and the unnumbered hint (FR16, FR17 — AC17, AC18)
# ═════════════════════════════════════════════════════════════════════════════

# `ordered_dir_names()` is duplicated verbatim in specclaw-update-status and
# specclaw-reconcile, by design and with a comment saying so. Pin it: a fix
# applied to one copy and not the other is exactly the drift that comment warns
# about, and nothing else in CI would notice.
extract_ordered_fn() {
  awk '/^ordered_dir_names\(\) \{/ { f = 1 } f { print } f && /^\}/ { exit }' "$1"
}
extract_ordered_fn "$USTATUS" >"$WORK/ord.status"
extract_ordered_fn "$RECONCILE" >"$WORK/ord.recon"
if [[ -s "$WORK/ord.status" ]]; then
  pass "O0a ordered_dir_names() was found in specclaw-update-status"
else
  fail "O0a ordered_dir_names() not found in specclaw-update-status"
fi
assert_same_file "O0b the two copies of ordered_dir_names() are byte-identical" \
  "$WORK/ord.status" "$WORK/ord.recon"

# active_order <specclaw_dir> — the change names listed under `## Active
# Changes`, in the order STATUS.md renders them.
active_order() {
  awk '/^## Active Changes/ { f = 1; next } /^## / { f = 0 } f && /^- /' "$1/STATUS.md" |
    awk -F'\\*\\*' '{ printf "%s%s", sep, $2; sep = " " }'
}

# completed_order <specclaw_dir> — the same, for `## Recently Completed`.
completed_order() {
  awk '/^## Recently Completed/ { f = 1; next } /^## / { f = 0 } f && /^- /' "$1/STATUS.md" |
    awk -F'\\*\\*' '{ printf "%s%s", sep, $2; sep = " " }'
}

make_render_fixture() {
  local d="$WORK/$1/.specclaw"
  mkdir -p "$d/changes"
  cat >"$d/config.yaml" <<'EOF'
version: 1
project:
  name: "numbering-fixture"
git:
  branch_prefix: "specclaw/"
EOF
  printf '%s' "$d"
}

# run_us <specclaw_dir> — regenerate STATUS.md with no network reachable, so the
# rendering is a pure function of the fixture.
run_us() {
  RC=0
  SPECCLAW_STATUS_NO_PR=1 "$USTATUS" "$1" >"$WORK/us.out" 2>"$WORK/us.err" || RC=$?
  OUT="$(cat "$WORK/us.out")"
  ERR="$(cat "$WORK/us.err")"
}

# ─── AC17: numeric ordering, unnumbered last ─────────────────────────────────
# Lexically `010-a` precedes `002-b`; numerically it does not. The fixture is
# chosen so the two orderings disagree, which is the only way this assertion can
# fail an implementation that sorts as strings.
S="$(make_render_fixture order)"
for c in 010-a 002-b unnumbered-c; do
  mkdir -p "$S/changes/$c"
  make_tasks "$S/changes/$c/tasks.md" 1 2
done
run_us "$S"
assert_eq "AC17a rendering exits 0" "0" "$RC"
assert_eq "AC17b numeric order, unnumbered last — not lexical" \
  "002-b 010-a unnumbered-c" "$(active_order "$S")"

# A legacy `YYYY-MM-DD-` folder is unnumbered per FR5a, so it joins the trailing
# group rather than sorting ahead of every real ordinal as "number 2026".
mkdir -p "$S/changes/2026-07-22-legacy"
make_tasks "$S/changes/2026-07-22-legacy/tasks.md" 1 2
run_us "$S"
assert_eq "AC17c a legacy date-prefixed folder sorts with the unnumbered group" \
  "002-b 010-a 2026-07-22-legacy unnumbered-c" "$(active_order "$S")"

# The archive listing uses the same ordering function.
mkdir -p "$S/changes/archive/001-first" "$S/changes/archive/012-later" \
  "$S/changes/archive/zz-unnumbered"
run_us "$S"
assert_eq "AC17d the archive listing is ordered the same way" \
  "001-first 012-later zz-unnumbered" "$(completed_order "$S")"

# specclaw-reconcile carries the same function and must agree.
RC=0
"$RECONCILE" "$S" >"$WORK/rec.out" 2>"$WORK/rec.err" || RC=$?
assert_eq "AC17e reconcile sweeps unmanaged changes without drift" "0" "$RC"
assert_eq "AC17f and in the same numeric order" \
  "002-b 010-a 2026-07-22-legacy unnumbered-c" \
  "$(sed -n 's/^▸ //p' "$WORK/rec.out" | tr '\n' ' ' | sed 's/ $//')"

# ─── AC18: the hint line, with its count, and absent at zero ─────────────────
# Double-quoted with escaped backticks: the backticks are literal markdown in the
# rendered hint, and this spelling says so without shellcheck reading them as an
# unexpanded command substitution.
HINT_MARK="run \`/specclaw:renumber\` to order them"

# Two unnumbered active folders plus one unnumbered archived folder — the
# archived one counts, because the backfill fixes it too.
run_us "$S"
assert_contains "AC18a the hint appears in STATUS.md with its count" \
  "_3 unnumbered changes · ${HINT_MARK}_" "$(cat "$S/STATUS.md")"
assert_contains "AC18b and on stdout, for /specclaw:status" \
  "3 unnumbered changes · ${HINT_MARK}" "$OUT"

# Singular at one.
S="$(make_render_fixture hint1)"
for c in 001-a unnumbered-b; do
  mkdir -p "$S/changes/$c"
  make_tasks "$S/changes/$c/tasks.md" 1 2
done
run_us "$S"
assert_contains "AC18c one unnumbered folder reads as singular" \
  "_1 unnumbered change · ${HINT_MARK}_" "$(cat "$S/STATUS.md")"

# Zero: no hint anywhere. Not a blank line, not a placeholder, not on stdout.
S="$(make_render_fixture hint0)"
for c in 001-a 002-b; do
  mkdir -p "$S/changes/$c"
  make_tasks "$S/changes/$c/tasks.md" 1 2
done
mkdir -p "$S/changes/archive/003-done"
run_us "$S"
assert_eq "AC18d rendering with nothing unnumbered exits 0" "0" "$RC"
assert_eq "AC18e no hint text in STATUS.md at all" "0" \
  "$(grep -c 'unnumbered' "$S/STATUS.md")"
assert_eq "AC18f nor any renumber pointer" "0" \
  "$(grep -c 'specclaw:renumber' "$S/STATUS.md")"
assert_lacks "AC18g nor on stdout" "unnumbered" "$OUT"
assert_eq "AC18h and the header keeps its shape — no stray blank line" \
  "**Project:** numbering-fixture" "$(sed -n '3p' "$S/STATUS.md")"
assert_eq "AC18i the ordering still holds without a hint" "001-a 002-b" "$(active_order "$S")"

# ─── Hermeticity ─────────────────────────────────────────────────────────────
# Nothing in this suite may write outside the temp workdir — in particular not
# into the repository's own .specclaw, which several cases read.
assert_eq "Ha every fixture artefact lives under the temp workdir" "0" \
  "$(find "$WORK" -name state.json -not -path "$WORK/*" | wc -l)"
# The AC6a case runs the real script against the repo's own .specclaw. It is a
# read, and this proves it: the working-tree status of that directory is
# identical to the snapshot taken before any case ran. Skipped outside a git
# checkout, where there is nothing to compare against.
if [ "$REPO_IS_GIT" -eq 1 ]; then
  assert_eq "Hb the repository's own .specclaw was only read, never written" \
    "$REPO_SPECCLAW_BEFORE" \
    "$(git -C "$REPO_ROOT" status --porcelain -- .specclaw 2>/dev/null || true)"
fi

echo
echo "─────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
