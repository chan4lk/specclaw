#!/usr/bin/env bash
# Change 060: specclaw-verify size — production lines against the merge-base, over pr.size_cap
# fails unless the proposal carries a Size waiver line.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/specclaw-verify"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0

lines() { seq 1 "$2" > "$1"; }
repo() { # repo <name> <pr-block>: base main with one file; HEAD on feat with change 001-x
  local d="$TMP/$1"
  mkdir -p "$d/.specclaw/changes/001-x" "$d/src"
  printf 'git:\n  base_branch: main\npr:\n%s\n' "$2" > "$d/.specclaw/config.yaml"
  echo '# Proposal' > "$d/.specclaw/changes/001-x/proposal.md"
  echo a > "$d/src/a.ts"
  git -C "$d" init -q -b main && git -C "$d" add -A && git -C "$d" commit -qm init
  git -C "$d" checkout -q -b feat
  echo "$d"
}
check() { # check <label> <repo> <want-exit> <want-substring>
  local out rc
  out="$(cd "$2" && "$BIN" size .specclaw 001-x 2>&1)"; rc=$?
  if [ "$rc" -eq "$3" ] && grep -qF -- "$4" <<<"$out"; then echo "PASS: $1"; else fail=1; echo "FAIL: $1 (exit $rc): $out"; fi
}

d="$(repo small '  size_cap: 10')"
lines "$d/src/b.ts" 3; git -C "$d" add -A; git -C "$d" commit -qm b
mkdir -p "$d/tests" "$d/src/generated"
lines "$d/tests/t.sh" 50; lines "$d/src/a.test.ts" 50; lines "$d/package-lock.json" 50; lines "$d/src/generated/api.ts" 50
lines "$d/.specclaw/changes/001-x/spec.md" 50
check "tests, lockfiles, generated files and .specclaw/ are not counted" "$d" 0 "size cap: 3 production lines (cap 10)"
lines "$d/src/new.ts" 4
check "untracked files count, over half the cap prints the split note" "$d" 0 "size cap: 7 production lines (cap 10); over half the cap, consider splitting."
lines "$d/src/more.ts" 4; git -C "$d" add -A
check "over the cap fails" "$d" 1 "size cap: 11 production lines is over the 10-line cap."
P="$d/.specclaw/changes/001-x/proposal.md"
for line in '**Size waiver**:' 'Size waiver:' 'Size waiver: **'; do
  printf '# Proposal\n%s\n' "$line" > "$P"
  check "a waiver with no reason ($line) does not pass" "$d" 1 "is over the 10-line cap"
done
for line in '**Size waiver:** one migration' '**Size waiver**: one migration' '- size waiver: one migration' 'Size waiver: one migration'; do
  printf '# Proposal\n%s\n' "$line" > "$P"
  check "a Size waiver line passes ($line)" "$d" 0 "with the waiver in .specclaw/changes/001-x/proposal.md"
done

d="$(repo off '  size_cap: 0')"; lines "$d/src/b.ts" 999
check "pr.size_cap 0 is off" "$d" 0 "size cap: off"

d="$(repo default '  test_policy: none')"; lines "$d/src/b.ts" 401
check "the default cap is 400" "$d" 1 "401 production lines is over the 400-line cap"

d="$(repo exclude '  size_cap: 10
  size_exclude: "docs/** *.md"')"
mkdir -p "$d/docs"; lines "$d/docs/x.ts" 50; lines "$d/README.md" 50; lines "$d/src/b.ts" 2
check "pr.size_exclude globs are not counted" "$d" 0 "size cap: 2 production lines (cap 10)"

d="$(repo deleted '  size_cap: 10')"; git -C "$d" rm -q src/a.ts
check "deleted lines count" "$d" 0 "size cap: 1 production lines (cap 10)"

d="$(repo nobase '  size_cap: 10')"; sed -i.bak 's/base_branch: main/base_branch: nosuch/' "$d/.specclaw/config.yaml"
check "no base branch is not counted and exits 2, never a pass" "$d" 2 "size cap: not counted, no base branch"

d="$(repo badgit '  size_cap: 10')"; lines "$d/src/b.ts" 2; echo garbage > "$d/.git/index"
check "a git failure after the base resolves is not counted and exits 2" "$d" 2 "size cap: not counted, git diff against"

# The shared base reader (lib/base-ref.sh) takes a single-quoted base after a column-0 comment, as branch.ts does.
d="$TMP/trunk"; mkdir -p "$d/.specclaw/changes/001-x" "$d/src"
printf "git:\n# the integration branch\n  base_branch: 'trunk'  # quoted\npr:\n  size_cap: 10\n" > "$d/.specclaw/config.yaml"
git -C "$d" init -q -b trunk && git -C "$d" add -A && git -C "$d" commit -qm init && git -C "$d" checkout -q -b feat
lines "$d/src/b.ts" 2
check "a single-quoted git.base_branch after a comment line is read" "$d" 0 "size cap: 2 production lines (cap 10)"

(( fail == 0 )) && echo "R060 AC-4 the size cap counts production lines and honours the waiver"
exit "$fail"
