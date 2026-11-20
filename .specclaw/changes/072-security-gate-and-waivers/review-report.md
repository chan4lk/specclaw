# Code Review Report: 072-security-gate-and-waivers

**Reviewed:** 2026-11-20 (re-review after `ee630e9` and `05f257a`)
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

2 findings: 0 BLOCK, 0 WARN, 2 NOTE. All earlier BLOCK and WARN findings are resolved.

D8 skipped: design.md absent. D9: no scope creep found; the fix commits touch only the gate, `specclaw-pr` and their tests.

## Earlier findings

- **[BLOCK] gate committed as 100644: resolved.** `git ls-tree HEAD plugins/specclaw/bin/specclaw-security-gate` now shows `100755`. In addition, `specclaw-pr` no longer skips a missing or non-executable gate. It sets `sec_rc=127` with "is missing or not executable", and that reaches the block or warn message like any other gate failure. Both ways of silently disabling the gate are closed.
- **[WARN] unparsable BLOCK headings read as clear: resolved.** I re-ran the gate on a `CHANGES_REQUESTED` fixture. Each of these produced an `unwaived` line and exit 1:
  - a path with a space
  - no dash
  - an en-dash
  - an emoji before `[BLOCK]`
  - a bare `BLOCK`
  - a backticked path with a bold rule

  A `CHANGES_REQUESTED` verdict with no readable BLOCK also exits 1, and a heading whose path or rule cannot be split prints "unwaived (path or rule unreadable)". Waiver matching still lifts a clean heading (exit 0, verified).
- **[WARN] verdict-less or empty report exits 0: resolved.** An empty file, `**Verdict:** NOT RUN`, and two conflicting verdict lines all exit 3. The verdict regex is anchored at line start, so a quoted `**Verdict:**` inside a finding cannot count.
- **[NOTE] bold or backticked fields and BOM: resolved.** `bare()` strips `*` and backticks from paths and rules, and `read()` opens with `utf-8-sig`.
- **[NOTE] empty `## Security` section skipped in `specclaw-build-context`: still open.** It is spec-vs-code wording only, with no user impact, so I am not raising it again as a finding.

## Findings

### [NOTE] plugins/specclaw/bin/specclaw-security-gate:23 — Correctness (lowercase `[block]` no longer counted)
**Problem:** `BLOCK_HEADING` is case-sensitive: `r"^\s*#{2,6}\s+(?:[^\w\s\[]+\s*)?(?:\[BLOCK\]|BLOCK\b)\s*(.*)$"`. The first version matched `### [block] …` (it used `re.I`), and now that line is skipped (verified). It still fails closed under a `CHANGES_REQUESTED` verdict, through the "no BLOCK heading could be read" path. But a report that says `APPROVED_WITH_NOTES` and also carries a lowercase `[block]` heading would read as clear. That mismatch is unlikely, since the agent template writes uppercase.
**Suggestion:** Use `(?i:\[BLOCK\])|BLOCK\b`, so the bracketed form is case-insensitive and the bare form stays strict. A heading like "Block diagram" then does not match.

### [NOTE] plugins/specclaw/bin/specclaw-security-gate:25 — Waiver matching (path containing ` - `)
**Problem:** `FIELDS` splits at the first separator that is followed by a space. A path containing ` - ` (for example `src/a - b.js:3 — B13`) parses as path `src/a` and cannot be waived. This is safe, because it fails toward "unwaived". It is also rare.
**Suggestion:** None needed. This is documented here so it is not a surprise.

## Checked and fine

- `specclaw-pr` Step 7-pre2:
  - It skips the gate only when `security_review` is exactly `false`.
  - It `die`s only when `security_review_block` is exactly `true`.
  - Exit 1, exit 3, exit 127 and any other code all produce a message.
  - The block comes before staging and `gh pr create`.
- `run-security-gate-tests.sh` passes in full, run here on Windows.
- The spec edits in FR-3, FR-4 and the edge cases match the new behaviour.

## Verdict Rationale

The accidental-bypass paths I raised are closed. The gate is now executable, `specclaw-pr` treats a gate it cannot run as a failure, and the script fails closed on unparsable BLOCK headings, missing, empty or conflicting verdicts, and a `CHANGES_REQUESTED` verdict with no readable BLOCK. The two remaining notes are low-risk edge cases. No BLOCK remains, so the verdict is APPROVED_WITH_NOTES.
