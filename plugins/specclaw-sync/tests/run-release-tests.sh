#!/usr/bin/env bash
# run-release-tests.sh — `specclaw-sync release <base> <target>`, the release gate by severity (change 064, AC-6).
#
# A scratch repo with debt.md and follow-ups.md at two refs. Offline. Plain bash + git + python3.
set -uo pipefail

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/specclaw-sync"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; FAILS=$((FAILS + 1)); cat "$TMP/out"; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

cd "$TMP" && git init -q -b main repo && cd repo || exit 2
mkdir -p .specclaw/changes/001-a .specclaw/changes/archive/000-z
printf '# Debt\n\n- [ ] [security blocker S1] `a.py:1` old secret (change 000-z, round 1) <!-- fp:aaa class:security -->\n' > .specclaw/debt.md
printf '# Follow-ups\n\n- [minor B1] `z.py:1` released before (round 1) <!-- fp:zzz -->\n' > .specclaw/changes/archive/000-z/follow-ups.md
git add -A && git commit -qm base && git tag base

cat >> .specclaw/debt.md <<'EOF'
- [ ] [other major B2] `b.py:2` slow loop (change 001-a, round 1) <!-- fp:bbb class:other -->
- [x] [law blocker L1] `c.py:3` fixed already (change 001-a, round 1) <!-- fp:ccc class:law -->
EOF
printf '# Follow-ups\n\n- [minor B3] `d.py:4` naming (round 2) <!-- fp:ddd -->\n' > .specclaw/changes/001-a/follow-ups.md
git add -A && git commit -qm ordinary && git tag ordinary

rel() { "$BIN" release "$@" > "$TMP/out" 2>&1; }
rel base ordinary; rc=$?
check "AC-6 ordinary debt in range: exit 0, both open items listed" '[ "$rc" = 0 ] && grep -q "slow loop" "$TMP/out" && grep -q "naming" "$TMP/out" && grep -q "2 open item" "$TMP/out"'
check "AC-6 ticked items and items already open at base are not listed" '! grep -q "fixed already" "$TMP/out" && ! grep -q "old secret" "$TMP/out" && ! grep -q "released before" "$TMP/out"'

printf -- '- [ ] [security major S2] `e.py:5` token in log (change 001-a, round 1) <!-- fp:eee class:security -->\n' >> .specclaw/debt.md
git add -A && git commit -qm security && git tag security
rel base security; rc=$?
check "AC-6 a security item in range: exit 1 and it is marked BLOCK" '[ "$rc" = 1 ] && grep -q "^BLOCK .*token in log" "$TMP/out"'
git checkout -q -b unclassified security && printf -- '- [ ] [unclassified major B8] `f.py:6` unlabelled (change 001-a, round 1) <!-- fp:fff class:unclassified -->\n' >> .specclaw/debt.md && git commit -qam unclassified
rel security HEAD; rc=$?
check "AC-6 an unclassified (unlabelled blocker/major) item blocks the release" '[ "$rc" = 1 ] && grep -q "^BLOCK unclassified" "$TMP/out"'
git checkout -q main
rel security security; rc=$?
check "AC-6 an empty range lists nothing, exit 0" '[ "$rc" = 0 ] && grep -q "0 open item" "$TMP/out"'

for form in 'release_gate:\n  block_on: [law]\n' 'release_gate:\n  block_on:\n    - law\n    - data-loss\n'; do
  git checkout -q security && printf "$form" > .specclaw/config.yaml && git add -A && git commit -qm cfg
  rel base HEAD; rc=$?
  check "AC-6 release_gate.block_on at the target without security: the item is listed, exit 0" '[ "$rc" = 0 ] && grep -q "token in log" "$TMP/out" && ! grep -q "^BLOCK" "$TMP/out"'
done
printf 'release_gate:\n  block_on: [Data Loss, security]\n' > .specclaw/config.yaml && git commit -qam cfg2
rel base HEAD; rc=$?
check "AC-6 block_on values are normalised like finding classes" '[ "$rc" = 1 ] && grep -q "block_on: data-loss, security" "$TMP/out"'

(cd .specclaw/changes && "$BIN" release base HEAD > "$TMP/out" 2>&1); rc=$?
check "AC-6 run from a subdirectory: same items, same exit" '[ "$rc" = 1 ] && grep -q "token in log" "$TMP/out"'
check "AC-6 block_on parses the same in specclaw-review and specclaw-sync" 'python3 - "$BIN" "$(dirname "$BIN")/../../specclaw-review/lib" <<"PY"
import importlib.machinery, importlib.util, sys
ld = importlib.machinery.SourceFileLoader("sync", sys.argv[1])
spec = importlib.util.spec_from_loader("sync", ld); sync = importlib.util.module_from_spec(spec); ld.exec_module(sync)
sys.path.insert(0, sys.argv[2]); import review_core as rc
def both(cfg):
    c = rc.Config.__new__(rc.Config); c.release_gate = rc.parse_block(cfg, "release_gate")
    out = []
    for f in (lambda: c.block_on, lambda: sync.block_on(cfg)):
        try:
            out.append(f())
        except (rc.ReviewError, sync.GateError):
            out.append("refused")
    return out
for cfg in ["", "release_gate:\n  block_on: []\n", "release_gate:\n  block_on: [law]\n",
            "release_gate:\n  block_on:\n    - law\n    - data-loss\n", "release_gate:\n  block_on: [Data Loss, \"security\"]\n",
            "release_gate:\n  block_on:\n  - law\n  - security\n", "release_gate:\n  block_on: [law, \x27security\x27]  # gate\n",
            "release_gate:\n  block_on:\n    - law  # note\n", "release_gate:\n  block_on: [law,]\n",
            "release_gate:\n  block_on: crash\n", "release_gate:\n  block_on: [securty]\n", "review:\n  block_on: [law]\n"]:
    a, b = both(cfg)
    assert a == b, (cfg, a, b)
assert both("release_gate:\n  block_on: crash\n") == ["refused", "refused"]
assert sync.CLASSES == rc.CLASSES and sync.DEFAULT_BLOCK_ON == rc.DEFAULT_BLOCK_ON
PY'
git checkout -q security && git tag -f pre-archive >/dev/null && mkdir -p .specclaw/changes/archive && git mv .specclaw/changes/001-a .specclaw/changes/archive/001-a && git commit -qm archive
rel pre-archive HEAD; rc=$?
check "AC-6 archiving a change (moving its follow-ups) adds no items" '[ "$rc" = 0 ] && grep -q "0 open item" "$TMP/out"'
printf 'release_gate:\n  block_on: [securty]\n' > .specclaw/config.yaml && git add -A && git commit -qm typo
rel base HEAD; rc=$?
check "AC-6 a misspelt block_on class is refused (exit 2), not a silently open gate" '[ "$rc" = 2 ] && grep -q "unknown class" "$TMP/out"'
rel base no-such-ref; rc=$?
check "AC-6 an unknown ref exits 2" '[ "$rc" = 2 ]'
rel base; rc=$?
check "AC-6 a missing argument exits 2" '[ "$rc" = 2 ]'

(( FAILS == 0 )) && echo "All release tests passed." || echo "$FAILS failed."
exit $(( FAILS > 0 ))
