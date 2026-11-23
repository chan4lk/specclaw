# Security Report: 072-security-gate-and-waivers

**Reviewed:** 2026-11-20
**Model:** claude-opus-5-5
**Verdict:** APPROVED_WITH_NOTES

## Threat Model

- **Assets:** the integrity of the PR security gate (an unwaived BLOCK must never reach a PR when `workflow.security_review_block` is true); the builder prompt (`## Stack Security Rules`); the PR body (`## Security waivers`).
- **Entry points:** `security-report.md` (written by the infosec-reviewer model, which reads untrusted diff text); `security-waivers.md` (written by people, or by any agent with repo write); `specclaw-security-gate` CLI args (`<specclaw-dir> <change>`); preset files resolved by `specclaw-presets`, including repo-local overrides, read by `specclaw-build-context`; `workflow.security_review` / `workflow.security_review_block` in `config.yaml`.
- **Trust boundaries:** model output → deterministic gate (report parsing); repo files → gate and PR body (waivers); repo files → builder prompt (presets, same trust as the existing `context.md` and knowledge hints); plugin install → executable bit of the gate script.

## Summary

1 finding: 0 BLOCK, 1 WARN, 0 NOTE

Re-review after `ee630e9` (fail-closed gate) and `05f257a` (fixture), over `ea1199a..HEAD`. Earlier findings:
- **Resolved** — `specclaw-pr:853` gate silently skipped when not executable: the gate is now `100755` in the index, and `specclaw-pr` sets `sec_rc=127` ("missing or not executable") when `-x` fails, which reaches the `*)` branch and dies under `security_review_block: true`.
- **Resolved, with a narrow residual (below)** — `specclaw-security-gate:18` unparsed BLOCK headings ignored: en dash, colon, space in path, emoji and bare `BLOCK` are now read (tested in `shapes`); a heading whose path or rule cannot be parsed is counted as unwaived; `CHANGES_REQUESTED` with no readable BLOCK exits 1.
- **Resolved** — `specclaw-security-gate:70` verdict-less report read as clear: `verdict_of` requires exactly one line-start `**Verdict:**` whose value is `APPROVED`, `APPROVED_WITH_NOTES` or `CHANGES_REQUESTED`; empty, missing, `NOT RUN`, garbled or conflicting verdicts exit 3 (tested in `empty`, `noverdict`, `notrunspace`, `twoverdicts`).

## Findings

### [WARN] plugins/specclaw/bin/specclaw-security-gate:23 — Errors (fail closed: some BLOCK headings still go uncounted)
**Code:** `BLOCK_HEADING = re.compile(r"^\s*#{2,6}\s+(?:[^\w\s\[]+\s*)?(?:\[BLOCK\]|BLOCK\b)\s*(.*)$")`
**Attack:** the fix dropped the old `re.I` and allows only punctuation or emoji before the tag, so `### [Block] …`, `### 🔴 Block …`, `### 1. [BLOCK] …` and `### Finding 2 [BLOCK] …` are not counted; when the report also holds one canonical BLOCK that is waived (so `blocks` is 1, not 0) or the model wrote `APPROVED_WITH_NOTES` alongside such a heading, the gate exits 0 and a blocking project opens the PR with that BLOCK unwaived — reachable through model drift or diff text that steers the reviewer's heading style.
**Fix:** add `re.I` and accept an optional enumeration before the tag (for example `(?:\d+[.)]\s*|[^\w\s\[]+\s*)*`), or count every `#`-heading line in which `\[?BLOCK\]?` appears before the first separator, case-insensitively; add `[Block]` and `1. [BLOCK]` cases to `run-security-gate-tests.sh`.

## Verdict Rationale

The three earlier fail-open paths are closed and covered by tests, and I found no new way to clear the gate through the verdict, waiver or path handling. The verdict must start its line and be the only one, so a finding that quotes `**Verdict:**` cannot add or override a verdict, and a fixture or code block that quotes one makes the gate exit 3, which fails closed. A BLOCK heading inside a code fence still counts. `bare()` stripping backticks and bold cannot widen a waiver: a waiver whose path or rule strips to empty is invalid, and matching stays exact on the normalised path and rule. A path the lazy `FIELDS` split cuts short (for example ` - ` inside a directory name) only makes the finding harder to waive, never easier. A missing or non-executable gate is now a failure. What remains is one WARN: the heading regex is now case-sensitive and does not allow a numbered prefix, so a BLOCK written in those styles is missed. It is exploitable only together with a waived canonical BLOCK or a verdict that contradicts the headings, so it stays WARN, not BLOCK. The waiver list at `specclaw-pr:470` still skips quietly when the gate is not executable. That now matters only in warn-only mode, after the gate has already printed a failure warning, so it is not a finding. No secrets, shell strings built from change names, or new dependencies were introduced.
