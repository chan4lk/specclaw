# Verify Report: lifecycle-bug-fixes

**Verdict:** PASS
**Date:** 2026-06-14

## Acceptance Criteria Results

| AC | Description (short) | Result | Evidence (command + key output) |
|----|---------------------|--------|---------------------------------|
| AC-1 (B2) | `validate-change verify` counts only real `` `T<n>` `` tasks; ignores fenced Legend lines | ✅ PASS | `validate-change .specclaw lifecycle-bug-fixes verify` → `✅ Ready for verify` (EXIT 0); status line `tasks.md (8/8 complete)`. /tmp fixture with a Legend fence containing two `` - [ ] `T<n>` `` lines + 2 real `[x]` tasks → `tasks.md (2/2 complete)` and `✅ Ready` — fence lines correctly NOT counted. |
| AC-2 (B3) | `verify collect` parses `AC1`/`AC-1`, with/without checkbox & bold | ✅ PASS | Real change: `collect … | jq '.acceptance_criteria | length'` → `9` (non-empty). /tmp spec mixing `- **AC1** —`, `- [ ] **AC-1:**`, `- [ ] AC-2` → all 3 parsed, each non-empty. |
| AC-3 (B4) | `changed_files` from `  - Files: \`...\`` bullet lines | ✅ PASS | Real change: `collect … | jq '.changed_files | length'` → `9`, paths include all touched bin/ scripts. /tmp tasks with `  - Files: \`src/x.ts\`, \`src/y.ts\`` → both extracted. |
| AC-4 (B5) | `verify-context` runs on BSD sed, non-empty payload, no sed errors | ✅ PASS | On `uname=Darwin`: `verify-context .specclaw lifecycle-bug-fixes` → EXIT 0, stdout 60999 bytes, stderr empty, `grep -c 'invalid command code'` = 0. Script uses `sed_i()` helper (`sed -i ''` on Darwin). |
| AC-5 (B6) | self-heal creates status.md; propose scaffolds it | ✅ PASS | (a) `verify update-status /tmp/ac5 heal PASS` with no status.md → `WARN: status.md not found; created from template`, `Updated status.md: Verify → ✅ Passed`, EXIT 0, file created with `\| Verify \| ✅ Passed \|`. (b) `skills/propose/SKILL.md:16` instructs generating `status.md` from `$CLAUDE_PLUGIN_ROOT/templates/status.md`. |
| AC-6 (B7) | `build_pr_title` from `# Proposal:` H1, no newline, within cap | ✅ PASS | Both scripts read `^#[[:space:]]*Proposal:`, strip `*`/backtick/CR/LF, cap (specclaw-pr:72 lines 307-309; specclaw-azdo-pr:128 line 235). Replicated against real proposal.md → GH `[specclaw] lifecycle-bug-fixes: lifecycle-bug-fixes — fix 9 bugs in t...` (len 72, 0 embedded newlines); ADO len 110 ≤ 128. Derived from H1, not Problem prose. |
| AC-7 (B8) | `adoapi_post` no `curl -f`; prints `ADO HTTP <code>: <body>`, non-zero on non-2xx | ✅ PASS | Code (lines 308-329): `curl -s` (no `-f`), `-w $'\n%{http_code}'`, splits code/body, on non-2xx `echo "ADO HTTP ${code}: ${body}" >&2; return 1`; 2xx returns body (empty-body-safe). Stubbed-curl simulation of 409 → stderr `ADO HTTP 409: {"message":"TF401179: dup PR",...}`, RC=1. |
| AC-8 (B9) | `finalize` checkout error includes `git checkout` stderr | ✅ PASS | specclaw-build lines 345/358: `checkout_err="$(git checkout "$main_branch" 2>&1 >/dev/null)"` then `errors+=("Failed to checkout $main_branch for merge: $checkout_err")` — captured stderr appended. |
| AC-9 (tests) | regression script runs & passes | ✅ PASS | `bash plugins/specclaw/tests/run-parser-tests.sh` → `13 passed, 0 failed`, EXIT 0. |

## Tests
`run-parser-tests.sh`: **13 passed / 0 failed** (EXIT 0). Covers parse-tasks T-id extraction & statuses, B2 fence/legend exclusion (1/2 and 1/3 lines), B3 three AC formats (AC-1/AC2/AC-3, no empty entries), B4 bulleted `Files:` paths, and NFR2 regression on the real in-repo `build-engine` change (6 tasks, 10 ACs found — no regression).

## Notes / Concerns
- **Legend-fence nuance (AC-1):** `parse-tasks` emits a benign `WARNING: Skipping malformed task … (no task ID): - [ ] \`T<n>\`` for the literal placeholder — correct (placeholder not counted); `validate-change`'s awk counters likewise exclude it via the `` `T[0-9]+` `` requirement and fence tracking.
- **No live ADO/GitHub calls possible** (no creds): AC-6 verified by replicating `build_pr_title` against the real proposal.md; AC-7 verified by code inspection plus a stubbed-`curl` simulation of a 409. AC-8 verified by code inspection.
- **JSON escaping is correct:** the real change's AC text contains literal backtick sequences; `json_escape` escapes backslashes first, so `collect` output is valid JSON (`jq .` succeeds).
- **Repo state untouched:** verifier's `update-status` test wrote only to /tmp; /tmp artifacts cleaned up.

## Verdict Rationale
All 9 acceptance criteria pass with direct evidence — three exercised live against the actual change (AC-1, AC-2/3 via collect, AC-4 on macOS BSD sed, AC-9 suite 13/0), and the PR/ADO/finalize criteria (AC-6/7/8) confirmed by code inspection plus behavioral replication/stub since no live credentials exist. No regressions and no blocking issues.
