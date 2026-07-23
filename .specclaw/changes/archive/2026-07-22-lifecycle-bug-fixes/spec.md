# Spec: lifecycle-bug-fixes

**Change:** lifecycle-bug-fixes
**Created:** 2026-06-14
**Status:** 🟡 Draft

## Overview

Fix 8 bugs (B2–B9 from `SPECCLAW-BUGS.md`) that break or silently degrade the
`propose → plan → build → verify → pr` lifecycle on macOS/BSD. The unifying theme is that the
`bin/` parsers (`validate-change`, `verify collect`) disagree with `parse-tasks` and with the
formats our own templates emit, plus three robustness defects (BSD `sed`, missing-file hard-fail,
swallowed errors). B1 (version-cache resolution) is parked and out of scope.

## Requirements

### Functional Requirements

- **FR1 (B2)** — `specclaw-validate-change … verify` MUST count only real tasks (backtick-wrapped
  `` `T<digits>` `` ids) and MUST ignore lines inside fenced code blocks, matching the behavior of
  `specclaw-parse-tasks`.
- **FR2 (B3)** — `specclaw-verify collect` MUST parse acceptance criteria written as `AC1` or
  `AC-1`, with or without a leading `- [ ]` checkbox and with or without `**bold**`.
- **FR3 (B4)** — `specclaw-verify collect` MUST parse `Files:` fields whether or not the line
  begins with a `- ` / `* ` list bullet (the format the tasks template emits: `  - Files: …`).
- **FR4 (B5)** — `specclaw-verify-context` MUST build the verify-agent template without crashing on
  BSD/macOS `sed` (no temp-file path interpolated into a `sed` script position).
- **FR5 (B6)** — A per-change `status.md` MUST exist after `propose`, and
  `specclaw-verify update-status` MUST NOT hard-fail when `status.md` is absent — it creates it.
- **FR6 (B7)** — Both `specclaw-azdo-pr` and `specclaw-pr` MUST build the PR title from the
  proposal's `# Proposal:` H1 line (not the Problem prose), strip markdown/newlines, and enforce
  the per-platform char cap with an ellipsis (128 ADO / 72 GitHub, unchanged).
- **FR7 (B8)** — `specclaw-azdo-pr` MUST surface the ADO HTTP status code and response body on any
  non-2xx instead of exiting 22 with no diagnostic.
- **FR8 (B9)** — `specclaw-build finalize` MUST include the underlying `git checkout` stderr in its
  error message when it cannot check out the base branch for the auto-merge.

### Non-Functional Requirements

- **NFR1** — Fixes are surgical: touch only the affected functions; match existing bash style
  (the portable `sedi`/`json_escape` patterns already in the repo).
- **NFR2** — Parser fixes MUST NOT regress the existing in-repo specs/tasks (e.g. `build-engine`,
  which uses `- [ ] **AC-1:**`). Verified by the regression suite.
- **NFR3** — Portable across BSD (macOS) and GNU (Linux) `sed`; no GNU-only flags.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- [ ] **AC-1 (B2):** GIVEN a `tasks.md` whose every real task is `[x]` and whose Legend fence
  contains `` - [ ] `T<n>` — <title> `` WHEN `specclaw-validate-change .specclaw <c> verify` runs
  THEN it reports ready (0 incomplete), agreeing with `specclaw-parse-tasks`.
- [ ] **AC-2 (B3):** GIVEN a spec with ACs written as `- **AC1** — …` (no checkbox, no hyphen)
  WHEN `specclaw-verify collect` runs THEN `acceptance_criteria` is non-empty and contains the AC
  text; AND the existing `- [ ] **AC-1:** …` format still parses.
- [ ] **AC-3 (B4):** GIVEN a `tasks.md` with `  - Files: \`path/a\`, \`path/b\`` WHEN
  `specclaw-verify collect` runs THEN `changed_files` contains `path/a` and `path/b`.
- [ ] **AC-4 (B5):** GIVEN macOS BSD `sed` WHEN `specclaw-verify-context` runs THEN it emits the
  verify-agent template payload with no `sed: … invalid command code` error and a non-empty body.
- [ ] **AC-5 (B6):** GIVEN a change with no `status.md` WHEN `specclaw-verify update-status
  .specclaw <c> PASS` runs THEN it creates `status.md` and writes the Verify verdict (exit 0);
  AND a fresh `propose` scaffolds `status.md`.
- [ ] **AC-6 (B7):** GIVEN a proposal with H1 `# Proposal: research-to-agents: …` WHEN
  `build_pr_title` runs in both `specclaw-azdo-pr` and `specclaw-pr` THEN the title derives from
  the H1 (not the Problem sentence), has no embedded newline, and is within the cap.
- [ ] **AC-7 (B8):** GIVEN an ADO POST that returns a non-2xx (e.g. 409 duplicate PR) WHEN
  `specclaw-azdo-pr` runs THEN it prints the HTTP status code and the ADO error body and exits
  non-zero with that diagnostic visible.
- [ ] **AC-8 (B9):** GIVEN `finalize` cannot check out the base branch WHEN it records the error
  THEN the error string contains the `git checkout` stderr (not just "Failed to checkout … for
  merge").
- [ ] **AC-9 (tests):** A regression script runs all parser fixtures (the exact `tasks.md`/`spec.md`
  shapes the templates emit) through `parse-tasks`, `validate-change`, and `verify collect` and
  passes; it is runnable from the repo with a single command.

## Edge Cases

- Legend fence with multiple checkbox-looking lines — none counted.
- A spec mixing both AC formats — all parsed, none duplicated.
- `Files:` line with no backticks (plain comma-separated) — still parsed (existing fallback kept).
- Proposal with no `# Proposal:` H1 — title falls back to `[specclaw] <change-name>`.
- ADO 2xx with empty body — treated as success (no false error).
- `finalize` when base branch checkout fails due to dirty tree — error names the reason.

## Dependencies

- `git`, `curl`, `awk`, `sed` (BSD + GNU), `python3` (already used), `gh`/ADO PAT for PR paths.
- No new runtime dependencies; no new test framework (plain bash regression script).

## Notes

- B1 (version/cache resolution) parked — out of scope, remains in `SPECCLAW-BUGS.md`.
- The PR title fix is applied in-place in each of the two scripts (no shared lib extraction — only
  two call sites; matches Rule 3 surgical-changes).
