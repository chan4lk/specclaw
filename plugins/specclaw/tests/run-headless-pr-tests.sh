#!/usr/bin/env bash
# run-headless-pr-tests.sh — finalize and the PR scripts with nobody at a terminal (change 043).
#
# A headless full-flow run (agent Bash, CI, /specclaw:auto) hit five defects:
#   finalize merged and deleted the change branch before verify and pr ran;
#   the test-policy prompt looped forever on a failed /dev/tty read;
#   `git push 2>/dev/null || true` never published a new branch;
#   the PR dispatch's own lock got committed with the change folder;
#   the PR bookkeeping (state.json, status.md, STATUS.md) was left uncommitted.
#
# No network: `gh` is a stub that logs its calls, origin is a local bare repo.
# Every script runs under run_bounded (perl setsid + alarm), so a regression of
# the prompt loop fails here instead of hanging CI.
#
# Plain bash + git + perl.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$PLUGIN_DIR/bin"
AZDO_PR_BIN="$PLUGIN_DIR/../specclaw-sync/bin/specclaw-azdo-pr"

for f in "$BIN_DIR/specclaw-pr" "$BIN_DIR/specclaw-build" "$BIN_DIR/specclaw-init" \
  "$BIN_DIR/specclaw-ensure-init" "$BIN_DIR/specclaw-check-staged" "$AZDO_PR_BIN"; do
  [[ -f "$f" ]] || { echo "FATAL: missing file: $f" >&2; exit 2; }
done
for b in git perl; do
  command -v "$b" >/dev/null 2>&1 || { echo "FATAL: $b is required for this suite" >&2; exit 2; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
assert_eq() {
  if [[ "$3" == "$2" ]]; then pass "$1 (= '$3')"; else fail "$1 — expected '$2', got '$3'"; fi
}
assert_contains() {
  if printf '%s' "$3" | grep -qF -- "$2"; then pass "$1"; else fail "$1 — expected to find: $2"; fi
}
assert_not_contains() {
  if printf '%s' "$3" | grep -qF -- "$2"; then fail "$1 — did not expect: $2"; else pass "$1"; fi
}

# The stub gh: logs every call, answers what specclaw-pr asks.
STUB="$WORK/stub"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${GH_LOG:?}"
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
  "pr create") echo "https://github.com/example/demo/pull/7" ;;
  "repo view") exit 1 ;;
esac
exit 0
EOF
chmod +x "$STUB/gh"
export GH_LOG="$WORK/gh.log"
export PATH="$STUB:$BIN_DIR:$PATH"

# run_bounded <secs> <cmd…> — no controlling terminal (setsid), stdin from
# /dev/null, killed after <secs>. Sets RC (124 on timeout) and OUT.
run_bounded() {
  local secs="$1"; shift
  RC=0
  perl -e '
    use POSIX ();
    my $secs = shift;
    my $pid = fork() // die "fork: $!";
    if ($pid == 0) { POSIX::setsid(); exec @ARGV or exit 127; }
    local $SIG{ALRM} = sub { kill "KILL", -$pid; kill "KILL", $pid; exit 124 };
    alarm $secs;
    waitpid($pid, 0);
    exit($? >> 8);
  ' "$secs" "$@" </dev/null >"$WORK/out" 2>&1 || RC=$?
  OUT="$(cat "$WORK/out")"
}

# make_proj <dir> [noremote] — an initialized project on branch specclaw/001-x
# with a verified change, origin a local bare repo holding main. Policy "none".
CH=001-x
make_proj() {
  local dir="$1" remote="${2:-}"
  mkdir -p "$dir"
  (
    cd "$dir" || exit 1
    git init -q -b main . && git config user.email t@t && git config user.name t
    specclaw-init . demo "" >/dev/null 2>&1
    sed -i.bak 's/test_policy: ""/test_policy: "none"/' .specclaw/config.yaml && rm -f .specclaw/config.yaml.bak
    git add -A && git commit -qm init
    if [[ "$remote" != noremote ]]; then
      git init -q --bare -b main "$dir.origin.git"   # HEAD → main, as a real remote has
      git remote add origin "$dir.origin.git"
      git push -q -u origin main 2>/dev/null
    fi
    git checkout -qb "specclaw/$CH"
    local c=".specclaw/changes/$CH"
    mkdir -p "$c"
    printf '# Proposal: Demo\n\n## Problem\np\n' >"$c/proposal.md"
    printf '# Spec\n\n## Acceptance Criteria\n- [ ] **AC-1:** one\n- [ ] **AC-2:** two\n' >"$c/spec.md"
    printf '# Design\n' >"$c/design.md"
    # shellcheck disable=SC2016  # literal backticks: the task-id markup
    printf '# Tasks\n\n- [x] `T1` — t\n  - Files: a.txt\n' >"$c/tasks.md"
    printf '# Verify\n\n**Verdict:** PASS\n' >"$c/verify-report.md"
    echo a >a.txt && git add a.txt && git commit -qm a
    local p
    for p in proposal spec design tasks build; do specclaw-set-phase .specclaw "$CH" "$p" "done" --force >/dev/null 2>&1; done
    specclaw-set-phase .specclaw "$CH" verify passed --force >/dev/null 2>&1
  )
}

# ─── AC-1 / AC-2: finalize merges only when asked ────────────────────────────
echo "--- AC-1/AC-2: finalize and git.merge_on_finalize ---"
P="$WORK/fin1"; make_proj "$P"
main_before="$(git -C "$P" rev-parse main)"
run_bounded 60 bash -c "cd '$P' && specclaw-build finalize .specclaw $CH"
assert_eq "AC-1a finalize exits 0 without the key" 0 "$RC"
assert_eq "AC-1b HEAD stays on the change branch" "specclaw/$CH" "$(git -C "$P" branch --show-current)"
assert_eq "AC-1c the change branch still exists" ok "$(git -C "$P" rev-parse -q --verify "specclaw/$CH" >/dev/null && echo ok)"
assert_eq "AC-1d main is unchanged" "$main_before" "$(git -C "$P" rev-parse main)"
assert_contains "AC-1e reports merged:false" '"merged": false' "$OUT"
assert_contains "AC-1f errors is empty" '"errors": []' "$OUT"

P="$WORK/fin2"; make_proj "$P"
printf '  merge_on_finalize: true\n' >"$WORK/mof"
sed -i.bak "/^git:/r $WORK/mof" "$P/.specclaw/config.yaml" && rm -f "$P/.specclaw/config.yaml.bak"
git -C "$P" commit -qam "opt in to merge_on_finalize"
run_bounded 60 bash -c "cd '$P' && specclaw-build finalize .specclaw $CH"
assert_contains "AC-2a reports merged:true" '"merged": true' "$OUT"
assert_eq "AC-2b HEAD is back on main" main "$(git -C "$P" branch --show-current)"
assert_eq "AC-2c the change branch was deleted" "" "$(git -C "$P" branch --list "specclaw/$CH")"

# ─── AC-3: no PR from the base branch ───────────────────────────────────────
echo "--- AC-3: refuse on the base branch / detached HEAD ---"
P="$WORK/base"; make_proj "$P"
git -C "$P" checkout -q main
: >"$GH_LOG"
run_bounded 20 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
assert_eq "AC-3a specclaw-pr on main exits 1" 1 "$RC"
assert_contains "AC-3b the message names the change branch" "specclaw/$CH" "$OUT"
assert_contains "AC-3c the message names merge_on_finalize" "git.merge_on_finalize" "$OUT"
assert_eq "AC-3d gh was never called" "" "$(cat "$GH_LOG")"
git -C "$P" checkout -q --detach "specclaw/$CH"
run_bounded 20 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
assert_eq "AC-3e specclaw-pr on a detached HEAD exits 1" 1 "$RC"
assert_contains "AC-3f the message says detached" "detached" "$OUT"

# specclaw-azdo-pr: fake credentials and git.base_branch, so the ADO API is never reached.
P="$WORK/azbase"; make_proj "$P"
git -C "$P" checkout -q main
sed -i.bak 's/^  base_branch: ""/  base_branch: "main"/' "$P/.specclaw/config.yaml" && rm -f "$P/.specclaw/config.yaml.bak"
run_bounded 20 env AZDO_TOKEN=x AZDO_ORG=o AZDO_PROJECT=p AZDO_REPO=r \
  bash -c "cd '$P' && bash '$AZDO_PR_BIN' .specclaw $CH"
assert_eq "AC-3g specclaw-azdo-pr on main exits 1" 1 "$RC"
assert_contains "AC-3h azdo's message names the change branch" "specclaw/$CH" "$OUT"

# ─── AC-4: no terminal, no policy → exit 2, never loop ───────────────────────
echo "--- AC-4: empty test_policy with no terminal ---"
P="$WORK/tty"; make_proj "$P"
sed -i.bak 's/test_policy: "none"/test_policy: ""/' "$P/.specclaw/config.yaml" && rm -f "$P/.specclaw/config.yaml.bak"
sed -i.bak 's/^  base_branch: ""/  base_branch: "main"/' "$P/.specclaw/config.yaml" && rm -f "$P/.specclaw/config.yaml.bak"
git -C "$P" commit -qam "empty policy"
cfg_before="$(cksum <"$P/.specclaw/config.yaml")"
run_bounded 20 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
assert_eq "AC-4a specclaw-pr exits 2 within 20s (124 = hung)" 2 "$RC"
assert_contains "AC-4b names pr.test_policy" "pr.test_policy" "$OUT"
assert_contains "AC-4c lists the values" "none | unit | e2e | both" "$OUT"
assert_eq "AC-4d config.yaml unchanged" "$cfg_before" "$(cksum <"$P/.specclaw/config.yaml")"
run_bounded 20 env AZDO_TOKEN=x AZDO_ORG=o AZDO_PROJECT=p AZDO_REPO=r \
  bash -c "cd '$P' && bash '$AZDO_PR_BIN' .specclaw $CH"
assert_eq "AC-4e specclaw-azdo-pr exits 2 within 20s (124 = hung)" 2 "$RC"
assert_contains "AC-4f azdo names pr.test_policy" "pr.test_policy" "$OUT"
assert_eq "AC-4g config.yaml unchanged by azdo" "$cfg_before" "$(cksum <"$P/.specclaw/config.yaml")"

# ─── AC-5 / AC-6 / AC-9: publish, keep the lock out, commit the bookkeeping ──
echo "--- AC-5/AC-6/AC-9: a headless PR on a fresh branch ---"
P="$WORK/ok"; make_proj "$P"
# A pre-0.8 project: no lock ignore rule, so the dispatch lock is untracked.
grep -vF '.lock/' "$P/.gitignore" >"$WORK/gi" && cp "$WORK/gi" "$P/.gitignore"
git -C "$P" commit -qam "pre-0.8 gitignore"
: >"$GH_LOG"
run_bounded 30 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
assert_eq "AC-5a specclaw-pr exits 0" 0 "$RC"
assert_eq "AC-5b the branch, bookkeeping commit included, is on origin" \
  "$(git -C "$P" rev-parse HEAD)" "$(git --git-dir="$P.origin.git" rev-parse -q --verify "refs/heads/specclaw/$CH")"
assert_contains "AC-5c gh pr create was called" "pr create" "$(cat "$GH_LOG")"
assert_eq "AC-5d the branch tracks origin" "origin/specclaw/$CH" \
  "$(git -C "$P" rev-parse --abbrev-ref '@{u}' 2>/dev/null)"
assert_eq "AC-6 no commit on the branch carries a .lock file" "" \
  "$(git -C "$P" log --name-only --format= main..HEAD | grep -F '/.lock/')"
assert_eq "AC-9a state.json, status.md and STATUS.md are committed" "" \
  "$(git -C "$P" status --porcelain -- ".specclaw/changes/$CH/state.json" ".specclaw/changes/$CH/status.md" .specclaw/STATUS.md)"
assert_contains "AC-9b the last commit records the PR" "record PR" "$(git -C "$P" log -1 --format=%s)"

# specclaw-build cuts the branch from origin/<base>, so its upstream starts as
# origin/main. A plain push there is refused (push.default=simple) — the branch
# must be published as itself, and main on origin must not move.
P="$WORK/upmain"; make_proj "$P"
git -C "$P" branch -q --set-upstream-to=origin/main
origin_main="$(git --git-dir="$P.origin.git" rev-parse main)"
: >"$GH_LOG"
run_bounded 30 env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=push.default GIT_CONFIG_VALUE_0=simple \
  bash -c "cd '$P' && specclaw-pr .specclaw $CH"
assert_eq "AC-5h upstream origin/main: specclaw-pr exits 0" 0 "$RC"
assert_eq "AC-5i … the branch is published as itself" \
  "$(git -C "$P" rev-parse HEAD)" "$(git --git-dir="$P.origin.git" rev-parse -q --verify "refs/heads/specclaw/$CH")"
assert_eq "AC-5j … main on origin did not move" "$origin_main" "$(git --git-dir="$P.origin.git" rev-parse main)"
assert_eq "AC-5k … the upstream is now origin/specclaw/$CH" "origin/specclaw/$CH" \
  "$(git -C "$P" rev-parse --abbrev-ref '@{u}' 2>/dev/null)"
# An upstream of its own name gets a plain push.
echo b >"$P/b.txt" && git -C "$P" add b.txt && git -C "$P" commit -qm b
# shellcheck disable=SC1091,SC2329  # lib sourced at runtime; die is called by it
( cd "$P" && die() { echo "DIE: $*"; exit 1; }; . "$PLUGIN_DIR/lib/pr-git.sh"; pr_publish_branch ) >/dev/null 2>&1
assert_eq "AC-5l an own-name upstream gets a plain push" \
  "$(git -C "$P" rev-parse HEAD)" "$(git --git-dir="$P.origin.git" rev-parse "refs/heads/specclaw/$CH")"

P="$WORK/norem"; make_proj "$P" noremote
: >"$GH_LOG"
run_bounded 30 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
assert_eq "AC-5e no remote at all exits 1" 1 "$RC"
assert_contains "AC-5f the message says no remote" "no git remote" "$OUT"
assert_not_contains "AC-5g gh pr create was never called" "pr create" "$(cat "$GH_LOG")"

# ─── AC-12: the PR body ticks what verify found ─────────────────────────────
echo "--- AC-12: acceptance criteria ticked in the PR body ---"
P="$WORK/tick-pass"; make_proj "$P"
: >"$GH_LOG"
run_bounded 30 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
body="$(cat "$GH_LOG")"
assert_contains "AC-12a PASS ticks AC-1" "- [x] **AC-1:** one" "$body"
assert_contains "AC-12b PASS ticks AC-2" "- [x] **AC-2:** two" "$body"
P="$WORK/tick-partial"; make_proj "$P"
printf '# Verify\n\nEarlier local run: PASS.\n\n**Verdict:** PARTIAL.\n\n| AC | Status |\n|---|---|\n| AC-1 | MET |\n| AC-2 | PENDING CI |\n' \
  >"$P/.specclaw/changes/$CH/verify-report.md"
: >"$GH_LOG"
run_bounded 30 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
body="$(cat "$GH_LOG")"
assert_not_contains "AC-12c PARTIAL reads the Verdict line, not the first PASS word" "**Verdict:** PASS" "$body"
assert_contains "AC-12d PARTIAL ticks the MET AC-1" "- [x] **AC-1:** one" "$body"
assert_contains "AC-12e PARTIAL leaves the pending AC-2 open" "- [ ] **AC-2:** two" "$body"

# ─── 072 AC-4: the security gate in specclaw-pr ─────────────────────────────
echo "--- 072 AC-4: unwaived BLOCK, block switch, waivers in the PR body ---"
# sec_proj <dir> <block true|false> — a project whose security-report.md holds one BLOCK.
sec_proj() {
  make_proj "$1"
  sed -i.bak "s/^  security_review_block: false/  security_review_block: $2/" "$1/.specclaw/config.yaml" && rm -f "$1/.specclaw/config.yaml.bak"
  printf '# Security

**Verdict:** CHANGES_REQUESTED

## Findings

### [BLOCK] src/a.js:3 — B13 SQL built from input
'     >"$1/.specclaw/changes/$CH/security-report.md"
  git -C "$1" commit -qm "security block switch" -- .specclaw/config.yaml >/dev/null || true  # no-op when block stays false; the change folder stays untracked, as make_proj leaves it
}
P="$WORK/sec-block"; sec_proj "$P" true
: >"$GH_LOG"
run_bounded 30 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
assert_eq "072-4a block true + unwaived BLOCK exits 1" 1 "$RC"
assert_contains "072-4b the message names the finding's path" "src/a.js" "$OUT"
assert_contains "072-4c the message says how to waive" "security-waivers.md" "$OUT"
assert_not_contains "072-4d gh pr create was never called" "pr create" "$(cat "$GH_LOG")"
P="$WORK/sec-warn"; sec_proj "$P" false
: >"$GH_LOG"
run_bounded 30 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
assert_eq "072-4e block false: specclaw-pr exits 0" 0 "$RC"
assert_contains "072-4f … and warns about the BLOCK" "WARNING: security gate: unwaived BLOCK" "$OUT"
assert_contains "072-4g … and the PR is created" "pr create" "$(cat "$GH_LOG")"
P="$WORK/sec-waive"; sec_proj "$P" true
printf -- '- Waiver: src/a.js | B13 | false alarm | input is a fixed enum
'   >"$P/.specclaw/changes/$CH/security-waivers.md"
: >"$GH_LOG"
run_bounded 30 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
assert_eq "072-4h a waived BLOCK passes even with block true" 0 "$RC"
body="$(cat "$GH_LOG")"
assert_contains "072-4i the PR body has a Security waivers section" "## Security waivers" "$body"
assert_contains "072-4j … carrying the reason" "input is a fixed enum" "$body"

# A gate that cannot list the waivers must never read as "there are none" (table-driven).
# Each row runs specclaw-pr from a copy of the plugin whose gate is replaced; block stays false so the PR opens.
PLUG="$WORK/plug-gate"
# row: <name> | <how the gate is broken> | <waivers file? yes|no> | <expected in the PR body>
while IFS='|' read -r name gate waivers want; do
  rm -rf "$PLUG"; mkdir -p "$PLUG"
  cp -R "$PLUGIN_DIR/bin" "$PLUGIN_DIR/lib" "$PLUGIN_DIR/references" "$PLUGIN_DIR/templates" "$PLUG/"
  case "$gate" in
    missing) rm -f "$PLUG/bin/specclaw-security-gate" ;;
    crash) printf '#!/usr/bin/env bash\necho boom >&2\nexit 3\n' >"$PLUG/bin/specclaw-security-gate"; chmod +x "$PLUG/bin/specclaw-security-gate" ;;
  esac
  P="$WORK/sec-list-$gate-$waivers"; sec_proj "$P" false
  [ "$waivers" = yes ] && printf -- '- Waiver: src/a.js | B13 | false alarm | listed elsewhere\n' >"$P/.specclaw/changes/$CH/security-waivers.md"
  : >"$GH_LOG"
  run_bounded 30 bash -c "cd '$P' && PATH='$PLUG/bin:$PATH' specclaw-pr .specclaw $CH"
  body="$(cat "$GH_LOG")"
  if [ "$want" = none ]; then
    assert_not_contains "072-4k gate $name, waivers $waivers: no waiver section" "## Security waivers" "$body"
  else
    assert_contains "072-4k gate $name, waivers $waivers: the PR body says the list could not be read" "$want" "$body"
  fi
done <<'ROWS'
missing|missing|yes|could not be read
crashing|crash|yes|could not be read
missing, nothing to list|missing|no|none
ROWS

# The block switch: every YAML spelling of true blocks; an unrecognised value is an error, never warn-only.
# row: <security_review_block value> | <expected message>
while IFS='|' read -r value want; do
  P="$WORK/sec-switch-$value"; sec_proj "$P" "$value"
  : >"$GH_LOG"
  run_bounded 30 bash -c "cd '$P' && specclaw-pr .specclaw $CH"
  assert_eq "072-4l security_review_block: $value stops the PR" 1 "$RC"
  assert_contains "072-4l … saying why ($value)" "$want" "$OUT"
  assert_not_contains "072-4l … before any PR is created ($value)" "pr create" "$(cat "$GH_LOG")"
done <<'ROWS'
True|unwaived BLOCK
yes|unwaived BLOCK
"on"|unwaived BLOCK
bogus|neither true nor false
ROWS

# ─── AC-7: a committed lock is suspicious ───────────────────────────────────
echo "--- AC-7: check-staged flags lock files ---"
P="$WORK/sus"; make_proj "$P"
mkdir -p "$P/.specclaw/changes/x/.lock"
echo '{}' >"$P/.specclaw/changes/x/.lock/meta.json"
git -C "$P" add -f .specclaw/changes/x/.lock/meta.json && git -C "$P" commit -qm "lock"
json="$(cd "$P" && specclaw-check-staged .specclaw "$CH" --json 2>/dev/null)"
assert_contains "AC-7 the lock file is under suspicious" \
  '"suspicious":[".specclaw/changes/x/.lock/meta.json"' "$json"
json="$(cd "$P" && specclaw-check-staged .specclaw x --json 2>/dev/null)"
assert_contains "AC-7b … even inside the change's own folder" \
  '"suspicious":[".specclaw/changes/x/.lock/meta.json"' "$json"

# ─── AC-8: ensure-init backfills the rule and warns, never untracks ─────────
echo "--- AC-8: ensure-init lock-rule backfill ---"
P="$WORK/ens"; make_proj "$P"
grep -vF '.lock/' "$P/.gitignore" >"$WORK/gi" && cp "$WORK/gi" "$P/.gitignore"
mkdir -p "$P/.specclaw/changes/old/.lock" && echo '{}' >"$P/.specclaw/changes/old/.lock/meta.json"
git -C "$P" add -A && git -C "$P" commit -qm "tracked lock"
(cd "$P" && specclaw-ensure-init .specclaw >/dev/null 2>"$WORK/ens1")
(cd "$P" && specclaw-ensure-init .specclaw >/dev/null 2>&1)
assert_eq "AC-8a the rule is added exactly once over two runs" 1 \
  "$(grep -cxF '.specclaw/changes/**/.lock/' "$P/.gitignore")"
assert_contains "AC-8b a tracked lock produces the warning" "git rm --cached" "$(cat "$WORK/ens1")"
assert_eq "AC-8c the lock is still tracked" ".specclaw/changes/old/.lock/meta.json" \
  "$(git -C "$P" ls-files -- '.specclaw/changes/old/.lock/*')"
git -C "$P" rm -q --cached -- '.specclaw/changes/**/.lock/*'
assert_eq "AC-8d silent once nothing is left to fix" "" "$(cd "$P" && specclaw-ensure-init .specclaw 2>&1)"
P="$WORK/ens-ro"; make_proj "$P"
grep -vF '.lock/' "$P/.gitignore" >"$WORK/gi" && cp "$WORK/gi" "$P/.gitignore" && chmod 444 "$P/.gitignore"
assert_eq "AC-8e a read-only .gitignore is skipped silently" "" "$(cd "$P" && specclaw-ensure-init .specclaw 2>&1)"
chmod 644 "$P/.gitignore"

echo
echo "=================================================="
echo "headless-pr: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
