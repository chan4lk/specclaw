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

fixture lowercase '**Verdict:** APPROVED_WITH_NOTES\n\n### [block] src/g.js:2 \xe2\x80\x94 B24 lowercase tag\n'
run lowercase
check "a lowercase [block] heading still blocks, whatever the verdict says (1)" '[ "$rc" -eq 1 ]'
# Each odd shape sits beside a waived normal BLOCK, so "no BLOCK read" cannot be what fails it.
for shape in '### [Block] src/h.js:1 \xe2\x80\x94 B21 mixed case' '### 1. [BLOCK] src/h.js:1 \xe2\x80\x94 B21 numbered' '### \xf0\x9f\x94\xb4 Block src/h.js:1 \xe2\x80\x94 B21 emoji, bare word'; do
  fixture oddshape "$HEAD$B1$shape"'\n' '- Waiver: src/api/user.js | Injection | accepted risk | reviewed\n'
  run oddshape
  check "odd heading still blocks: $(printf '%b' "$shape" | cut -c5-)" '[ "$rc" -eq 1 ] && grep -q "unwaived: .*src/h.js" <<<"$out"'
done

# No catastrophic backtracking: long punctuation-only headings that never reach a tag finish fast.
# perl alarm bounds the run, so a regression fails here instead of hanging CI.
for run_ in '!' '.-' '1.!'; do
  long="$(printf "%0.s$run_" $(seq 1 400))"
  fixture redos "**Verdict:** APPROVED\n\n### $long tail\n## $long\n"
  out="$(perl -e 'alarm 10; exec @ARGV' "$GATE" "$TMP/sc" redos 2>&1)"; rc=$?
  check "a 400-run '$run_' heading is scanned in under 10s (no ReDoS)" '[ "$rc" -eq 0 ]'
done

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

# Path matching, table-driven: <heading path> | <waiver path> | <expected exit>.
# POSIX paths are case-sensitive; a Windows spelling on either side folds case for the pair.
while IFS='|' read -r hpath wpath want; do
  fixture pathcase "$HEAD"'### [BLOCK] '"$hpath"':3 \xe2\x80\x94 B13 x\n' "- Waiver: $wpath | B13 | accepted risk | ok\n"
  run pathcase
  check "path '$hpath' vs waiver '$wpath' exits $want" '[ "$rc" -eq "$want" ]'
done <<'ROWS'
src/Auth.js|src/auth.js|1
src/auth.js|src/auth.js|0
C:\\Src\\A.js|c:/src/a.js|0
C:/Src/A.js|c:\\src\\a.js|0
src\\Lib\\X.cs|src/lib/x.cs|0
src/lib/x.cs|src\\Lib\\X.cs|0
ROWS

# Heading location and rule spellings, table-driven: <heading path and suffix> | <heading rule> | <waiver rule> | <exit>.
while IFS='|' read -r hloc hrule wrule want; do
  fixture shapes2 "$HEAD"'### [BLOCK] '"$hloc"' \xe2\x80\x94 '"$hrule"' x\n' "- Waiver: src/a.js | $wrule | accepted risk | ok\n"
  run shapes2
  check "heading '$hloc — $hrule' vs waiver rule '$wrule' exits $want" '[ "$rc" -eq "$want" ]'
done <<'ROWS'
src/a.js:3-7|B13|B13|0
src/a.js:42:5|B13|B13|0
src/a.js|`B13`,|B13|0
src/a.js:9|(B13)|`b13`|0
src/a.js:9|B13.1|B13|1
src/a.js:9|B13|B14|1
src/a.js:9|---|***|1
src/a.js:9|(?)|(!)|1
ROWS

# Verdict reading, table-driven: <verdict line value> | <expected exit> (no findings in the report).
while IFS='|' read -r value want; do
  fixture verdicts "**Verdict:** $value\n\n## Findings\n\nNo findings.\n"
  run verdicts
  check "verdict '$value' exits $want" '[ "$rc" -eq "$want" ]'
done <<'ROWS'
APPROVED|0
APPROVED_WITH_NOTES|0
APPROVED WITH NOTES|0
APPROVED_WITH_NOTES (2 WARN)|0
approved with notes|0
CHANGES REQUESTED|1
CHANGES_REQUESTED|1
NOT_RUN|3
NOT RUN (timeout)|3
not run|3
CHANGES|3
|3
ROWS

# --headings: the one heading definition, exported for the eval runner (every severity, any file).
printf '%b' '## 1. \xf0\x9f\x94\xb4 Block src/a.js:1 \xe2\x80\x94 B16 x\n### [warn] src/b.js:2 - B14 y\n#### NOTE src/c.js:3 - B10 z\nplain line with [BLOCK] in it\n' > "$TMP/headings.md"
out="$("$GATE" --headings "$TMP/headings.md")"; rc=$?
check "--headings prints every finding heading with its severity, nothing else" '[ "$rc" -eq 0 ] && [ "$(cut -f1 <<<"$out" | tr "\n" " ")" = "BLOCK WARN NOTE " ]'
out="$("$GATE" --headings "$TMP/no-such-file.md" 2>&1)"; rc=$?
check "--headings with a missing file is a usage error (2)" '[ "$rc" -eq 2 ]'

# --verdict: the one verdict reading, exported for the eval runner.
printf '%b' 'Some prose.\n**Verdict:** APPROVED WITH NOTES (1 WARN)\n' > "$TMP/v-ok.md"
printf '%b' 'I cannot review this file. No findings to report.\n' > "$TMP/v-none.md"
out="$("$GATE" --verdict "$TMP/v-ok.md")"; rc=$?
check "--verdict prints the normalised verdict (0)" '[ "$rc" -eq 0 ] && [ "$out" = APPROVED_WITH_NOTES ]'
out="$("$GATE" --verdict "$TMP/v-none.md")"; rc=$?
check "--verdict on prose with no verdict exits 3" '[ "$rc" -eq 3 ]'

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
