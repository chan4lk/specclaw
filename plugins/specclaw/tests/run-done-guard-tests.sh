#!/usr/bin/env bash
# Change 060: hooks/done-guard, the Stop hook. Exit 2 with the missing step on stderr only for a
# change touched on this branch whose tasks are all done; exit 0 everywhere else.
set -uo pipefail
GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/done-guard"
SET_PHASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/specclaw-set-phase"
TMP="$(mktemp -d)"
trap 'chmod -R u+rw "${TMP:?}" 2>/dev/null; rm -rf "${TMP:?}"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
STUB="$TMP/stub"
mkdir -p "$STUB"
BASE_PATH="/usr/bin:/bin:$(dirname "$(command -v git)")"
fail=0

commit() { # commit <repo> <date> <msg>
  git -C "$1" add -A && GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" commit -qm "$3"
}
change() { # change <repo> <name> <tasks> [verify-status [verdict]]: state.json comes from the real writer
  local d="$1/.specclaw/changes/$2"
  mkdir -p "$d"
  printf '%s\n' "$3" > "$d/tasks.md"
  "$SET_PHASE" "$1/.specclaw" "$2" proposal approved >/dev/null 2>&1
  [ -z "${4:-}" ] || "$SET_PHASE" "$1/.specclaw" "$2" verify "$4" ${5:+--verdict "$5"} >/dev/null 2>&1
}
repo() { # repo <name> [base_branch]: main holds an old all-done change with no verify; HEAD is on feat
  local d="$TMP/$1"
  mkdir -p "$d/.specclaw/changes" "$d/src"
  printf 'git:\n  base_branch: %s\n' "${2:-main}" > "$d/.specclaw/config.yaml"
  echo a > "$d/src/a.ts"
  change "$d" 001-old '- [x] `T1` — old'
  git -C "$d" init -q -b main && commit "$d" 2026-01-01T00:00:00Z init
  git -C "$d" checkout -q -b feat
  echo "$d"
}
DONE='- [x] `T1` — a
- [x] `T2` — b'
OPEN='- [x] `T1` — a
- [ ] `T2` — b'

check() { # check <label> <repo> <want-exit> <want-stderr-substring> [stdin] [path]
  local out rc
  out="$(cd "$2" && printf '%s' "${5:-{\}}" | PATH="${6:-$BASE_PATH}" "$GUARD" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq "$3" ] && { [ -z "$4" ] || grep -qF -- "$4" <<<"$out"; } && { [ "$3" -ne 0 ] || [ -z "$out" ]; }; then
    echo "PASS: $1"
  else
    fail=1; echo "FAIL: $1 (exit $rc): $out"
  fi
}

d="$(repo committed)"; change "$d" 002-x "$DONE"; commit "$d" 2026-01-02T00:00:00Z work
check "a committed all-done change with no verify exits 2" "$d" 2 "002-x has every task done, but no verify verdict"
check "stop_hook_active true exits 0" "$d" 0 "" '{"stop_hook_active": true}'
grep -q 001-old <<<"$(cd "$d" && "$GUARD" </dev/null 2>&1)" && { fail=1; echo "FAIL: the untouched change was named"; } || echo "PASS: a change untouched on this branch is not named"

d="$(repo untracked)"; change "$d" 002-x "$DONE"
check "an untracked all-done change with no verify exits 2" "$d" 2 "002-x has every task done, but no verify verdict"

d="$(repo open)"; change "$d" 002-x "$OPEN"
check "a change with an open task exits 0" "$d" 0 ""

d="$(repo failed)"; change "$d" 002-x "$DONE" failed FAIL
check "a FAIL verify exits 2" "$d" 2 "its verify verdict is FAIL, not PASS"

d="$(repo fresh)"; change "$d" 002-x "$DONE" passed PASS; commit "$d" 2026-01-02T00:00:00Z work
check "a PASS verify newer than the last code commit exits 0" "$d" 0 ""
echo b > "$d/src/a.ts"; commit "$d" 2099-01-01T00:00:00Z late
check "code committed after the verify exits 2" "$d" 2 "code was committed after its verify"

d="$(repo specclaw-only)"; change "$d" 002-x "$DONE" passed PASS; commit "$d" 2099-01-01T00:00:00Z report
check "a later commit only under .specclaw/ keeps the verify for HEAD" "$d" 0 ""

d="$(repo lean)"; change "$d" 002-x "$DONE" done
check "a lean verify (status done, no verdict) counts as PASS" "$d" 0 ""

d="$(repo review)"; change "$d" 002-x "$DONE" passed PASS
printf '#!/bin/sh\necho "Review: OPEN — 1 rounds"\nexit 1\n' > "$STUB/specclaw-review"; chmod +x "$STUB/specclaw-review"
check "a non-clean review verdict exits 2 when specclaw-review is installed" "$d" 2 "its review is not clean: Review: OPEN" "{}" "$STUB:$BASE_PATH"
printf '#!/bin/sh\necho "Review: CLEAN"\n' > "$STUB/specclaw-review"
check "a clean review verdict and a PASS verify exit 0" "$d" 0 "" "{}" "$STUB:$BASE_PATH"

d="$(repo nobase nosuch)"; change "$d" 002-x "$DONE" passed PASS
check "without a base every active change is checked" "$d" 2 "001-old has every task done, but no verify verdict"

d="$(repo badjson)"; change "$d" 002-x "$DONE"; echo '{"phases": {' > "$d/.specclaw/changes/002-x/state.json"
check "an unreadable state.json is skipped, never reported as a verdict" "$d" 0 ""

d="$(repo noconfig)"; change "$d" 002-x "$DONE"; rm "$d/.specclaw/config.yaml"
check "no .specclaw/config.yaml exits 0" "$d" 0 ""

d="$(repo broken)"; change "$d" 002-x "$DONE"; chmod 000 "$d/.specclaw/changes/002-x/tasks.md"
check "an internal error exits 0" "$d" 0 ""

(( fail == 0 )) && echo "R060 AC-3 the done guard holds only touched, all-done changes missing a step"
exit "$fail"
