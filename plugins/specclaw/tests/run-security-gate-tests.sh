#!/usr/bin/env bash
# run-security-gate-tests.sh — change 072, AC-3: specclaw-security-gate exit codes, waiver matching
# and the --waivers list, against fixtures in a temp dir only.
# shellcheck disable=SC2016,SC2329  # check() evals its single-quoted condition later, by design
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$PLUGIN_DIR/bin/specclaw-security-gate"
FAILS=0
ok() { echo "PASS: $1"; }
ko() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fixture <name> <report or -> [waivers]: a change folder under $TMP/sc; "-" means no report.
fixture() {
  mkdir -p "$TMP/sc/changes/$1"
  [ "$2" = "-" ] || printf '%b' "$2" > "$TMP/sc/changes/$1/security-report.md"
  [ -z "${3:-}" ] || printf '%b' "$3" > "$TMP/sc/changes/$1/security-waivers.md"
}
# run <name> [--waivers]: sets $rc and $out
run() { out="$("$GATE" "$TMP/sc" "$@" 2>&1)"; rc=$?; }

HEAD='# Security Report: x\n\n**Verdict:** CHANGES_REQUESTED\n\n## Findings\n\n'
B1='### [BLOCK] src/api/user.js:42 — Injection. SQL built from input\n'
B2='### [BLOCK] src/auth.js:7 -- Secrets: token in source\n'

fixture clean '# Security Report: x\n\n**Verdict:** APPROVED_WITH_NOTES\n\n### [WARN] src/a.js:1 — Logging x\n### [NOTE] src/b.js:2 — Headers y\n'
run clean
check "no BLOCK exits 0" '[ "$rc" -eq 0 ]'

fixture allwaived "$HEAD$B1$B2" '# Waivers\n\n- Waiver: src/api/user.js | injection | accepted risk | parameterised upstream | really\n  * **Waiver:** src\\auth.js:99 | SECRETS | False Alarm | test fixture key\n'
run allwaived
check "every BLOCK waived exits 0" '[ "$rc" -eq 0 ]'
check "waived BLOCK printed with kind and reason (| kept in reason)" 'grep -q "accepted risk: parameterised upstream | really" <<<"$out"'
check "waived BLOCK with \\ path and bold label printed" 'grep -q "false alarm: test fixture key" <<<"$out"'

fixture oneopen "$HEAD$B1$B2" '- Waiver: src/api/user.js | Injection | accepted risk | reviewed\n'
run oneopen
check "one unwaived BLOCK exits 1" '[ "$rc" -eq 1 ]'
check "unwaived heading printed" 'grep -q "unwaived: ### \[BLOCK\] src/auth.js:7 -- Secrets" <<<"$out"'

fixture nohead '**Verdict:** CHANGES_REQUESTED\n### [BLOCK] lib/x.py - Access missing check\n'
run nohead
check "BLOCK outside ## Findings, '-' dash, no :line still blocks" '[ "$rc" -eq 1 ] && grep -q "lib/x.py" <<<"$out"'

fixture missing -
run missing
check "missing report exits 3" '[ "$rc" -eq 3 ] && grep -q "security review did not run" <<<"$out"'

fixture notrun '# Security Report: x\n\n**Verdict:** NOT_RUN\n\nNo changed files were provided.\n'
run notrun
check "NOT_RUN exits 3" '[ "$rc" -eq 3 ] && grep -q "security review did not run" <<<"$out"'

fixture emptyreason "$HEAD$B1" '- Waiver: src/api/user.js | Injection | accepted risk |   \n- Waiver: src/api/user.js | Injection | maybe | why\n- Waiver: src/api/user.js | Injection | accepted risk\n'
run emptyreason
check "empty-reason waiver: block stays (1)" '[ "$rc" -eq 1 ]'
check "empty reason, unknown kind, short line each printed invalid" '[ "$(grep -c "^invalid waiver:" <<<"$out")" -eq 3 ]'

fixture otherfile "$HEAD$B1" '- Waiver: src/api/admin.js | Injection | accepted risk | elsewhere\n'
run otherfile
check "same rule on another file waives nothing (1)" '[ "$rc" -eq 1 ]'

fixture otherrule "$HEAD$B1" '- Waiver: src/api/user.js | Secrets | accepted risk | wrong rule\n'
run otherrule
check "other rule on the same file waives nothing (1)" '[ "$rc" -eq 1 ]'

fixture windows "$HEAD"'### [BLOCK] C:\\repo\\src\\app.cs:12 — Access no auth\n' '- Waiver: C:/repo/src/app.cs | access | accepted risk | internal only\n'
run windows
check "Windows drive-letter path waiver matches (0)" '[ "$rc" -eq 0 ]'

# Fail closed (review findings on 072): every BLOCK-shaped heading counts, an unreadable one stays unwaived.
fixture shapes "$HEAD"'### [BLOCK] src/my dir/a.js:3 \xe2\x80\x93 B13 en dash, space in path\n### \xf0\x9f\x94\xb4 [BLOCK] src/b.js:4 \xe2\x80\x94 B21 emoji first\n### BLOCK src/c.js:5 \xe2\x80\x94 B22 no brackets\n### [BLOCK] src/d.js:6 B8 no separator\n' \
  '- Waiver: src/my dir/a.js | B13 | accepted risk | ok\n- Waiver: src/b.js | B21 | accepted risk | ok\n- Waiver: src/c.js | B22 | accepted risk | ok\n'
run shapes
check "en dash, space in path, emoji, bare BLOCK are all read and waivable" '! grep -q "unwaived: .*src/\(my dir/a\|b\|c\)\.js" <<<"$out" && [ "$(grep -c "^waived" <<<"$out")" -eq 3 ]'
check "a BLOCK heading with no separator is unwaived as unreadable (1)" '[ "$rc" -eq 1 ] && grep -q "unwaived (path or rule unreadable): .*src/d.js" <<<"$out"'

fixture boldrule "$HEAD"'### [BLOCK] `src/e.js`:9 \xe2\x80\x94 **B23** bold rule, backticked path\n' '\xef\xbb\xbf- Waiver: `src/e.js` | **B23** | false alarm | test double\n'
run boldrule
check "bold rule, backticked path and a BOM-led waiver still match (0)" '[ "$rc" -eq 0 ]'

fixture empty ''
run empty
check "an empty report exits 3" '[ "$rc" -eq 3 ]'
fixture noverdict '# Security Report: x\n\n## Findings\n\nNo findings.\n'
run noverdict
check "a report with no verdict line exits 3" '[ "$rc" -eq 3 ]'
fixture notrunspace '# Security Report: x\n\n**Verdict:** NOT RUN\n'
run notrunspace
check "NOT RUN with a space exits 3" '[ "$rc" -eq 3 ]'
fixture twoverdicts '**Verdict:** APPROVED\n\n**Verdict:** CHANGES_REQUESTED\n'
run twoverdicts
check "conflicting verdict lines exit 3" '[ "$rc" -eq 3 ]'
fixture quoted '**Verdict:** APPROVED_WITH_NOTES\n\n### [WARN] src/f.js:1 \xe2\x80\x94 B3 Fix: require one `**Verdict:**` line\n'
run quoted
check "a finding that quotes **Verdict:** mid-line is not a second verdict (0)" '[ "$rc" -eq 0 ]'
fixture crnoblock '# Security Report: x\n\n**Verdict:** CHANGES_REQUESTED\n\n## Findings\n\nSomething is wrong but no heading.\n'
run crnoblock
check "CHANGES_REQUESTED with no readable BLOCK exits 1" '[ "$rc" -eq 1 ] && grep -q "no BLOCK heading could be read" <<<"$out"'

run allwaived --waivers
check "--waivers lists valid waivers as markdown" '[ "$rc" -eq 0 ] && [ "$(grep -c "^- \`" <<<"$out")" -eq 2 ] && grep -q "^- \`src/api/user.js\` — injection — accepted risk: parameterised upstream | really$" <<<"$out"'
run emptyreason --waivers
check "--waivers omits invalid waivers" '[ "$rc" -eq 0 ] && [ -z "$out" ]'
run missing --waivers
check "--waivers exits 0 with no report" '[ "$rc" -eq 0 ]'

"$GATE" "$TMP/sc" >/dev/null 2>&1; rc=$?
check "missing change arg exits 2" '[ "$rc" -eq 2 ]'
"$GATE" "$TMP/sc" nope >/dev/null 2>&1; rc=$?
check "missing change folder exits 2" '[ "$rc" -eq 2 ]'
"$GATE" "$TMP/sc" clean --bogus >/dev/null 2>&1; rc=$?
check "unknown extra arg exits 2" '[ "$rc" -eq 2 ]'

echo
[ "$FAILS" -eq 0 ] && echo "All security-gate tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
