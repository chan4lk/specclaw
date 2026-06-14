# Proposal: lifecycle-bug-fixes — fix 9 bugs in the propose→plan→build→verify→pr lifecycle

**Created:** 2026-06-14
**Status:** 🟡 Draft

## Problem

Running the full `propose → plan → build → verify → pr-azdo` lifecycle for a real change on
macOS surfaced **9 bugs** (documented in `SPECCLAW-BUGS.md`), four of them 🔴 blocking. The
lifecycle currently fails or degrades silently on a clean, template-generated change:

- **Parser disagreement** — `parse-tasks`, `validate-change`, and `verify collect` interpret the
  *same* `tasks.md`/`spec.md` that our own templates emit in incompatible ways. The template and
  the parsers are not a single source of truth.
- **BSD/macOS portability** — `specclaw-verify-context` embeds a temp-file path into a `sed`
  script position; GNU sed tolerates it, BSD sed (macOS default) crashes (`invalid command code`).
- **Tools assume files exist or swallow errors** — `verify update-status` hard-fails when a
  per-change `status.md` is absent; `azdo-pr` builds the PR title from the wrong field and hides
  the ADO HTTP error body (`curl --fail`, exit 22); `build finalize` reports a non-actionable
  merge failure.
- **Version skew** — command→skill→bin resolution can load skill bodies from an older cached
  version (0.2.2) than the bin scripts (0.4.2), so docs describe a different contract than the code.

Net effect: the happy path through our own lifecycle does not work end-to-end on macOS without
manual workarounds (hand-edited templates, hand-built verify payloads, direct REST PR creation).

## Proposed Solution

Fix each bug at its root, prioritizing the 🔴 blockers, and add regression coverage so the
template→parser contract stays a single source of truth.

- **B2** — `specclaw-validate-change` verify: ignore fenced code blocks and require a real task id
  (`T\d+`) when counting incomplete tasks, matching `specclaw-parse-tasks`.
- **B3** — `specclaw-verify collect`: accept `AC1`/`AC-1`, with or without a checkbox, when
  parsing acceptance criteria.
- **B4** — `specclaw-verify collect`: allow an optional leading `- `/`* ` bullet on `Files:` lines.
- **B5** — `specclaw-verify-context`: remove the embedded-path `sed` call; replace with a portable
  approach (awk/python or in-host read-replace) that works on BSD and GNU sed.
- **B6** — scaffold a per-change `status.md` in `propose` (and/or have `verify update-status`
  create it if absent) so update-status never hard-fails.
- **B7** — build the PR title from the proposal H1 / `# Proposal:` line, sanitize newlines,
  enforce the char cap with an ellipsis. **Confirmed to affect BOTH paths:** `specclaw-pr`
  (GitHub) and `specclaw-azdo-pr` share an identical `build_pr_title` that takes the first
  non-header line (the Problem prose) — GitHub caps at 72, ADO at 128. Fix both.
- **B8** — `specclaw-azdo-pr`: drop `curl --fail` (or capture `%{http_code}` + body) and print the
  ADO error payload on any non-2xx. (ADO-specific — the GitHub path uses `gh pr create`, which
  already surfaces errors.)
- **B9** — `specclaw-build finalize`: surface the underlying `git checkout` stderr and skip
  auto-merge gracefully when the base branch can't be checked out, explaining why.

### Parked
- **B1** (version/cache resolution) — **parked** by request. Not addressed in this change;
  remains documented in `SPECCLAW-BUGS.md` for later (likely an install/packaging artifact rather
  than a code fix in this repo).

## Scope

### In Scope
- Fixes to the affected `bin/` scripts: `specclaw-validate-change`, `specclaw-verify`,
  `specclaw-verify-context`, `specclaw-azdo-pr`, `specclaw-pr` (GitHub — shares the B7 title bug),
  `specclaw-build`.
- `propose` skill / template change to scaffold per-change `status.md` (B6).
- Regression tests covering the template→parser contract (the exact `tasks.md`/`spec.md` our
  templates generate must round-trip through all three parsers).

### Out of Scope
- **B1** (version/cache resolution) — parked, see below.
- Redesigning the spec/tasks template format beyond what the parser fixes require.
- New lifecycle features or commands.

## Impact

- **Files affected:** ~6–8 (estimated) — 5 bin scripts, 1 template, propose skill, plus tests.
- **Complexity:** medium
- **Risk:** medium — parser changes touch the core lifecycle; regression tests required to avoid
  breaking existing valid `tasks.md`/`spec.md` documents in-repo.

## Open Questions

1. **B6 placement** — scaffold `status.md` in `propose` (preferred, fixes it for all future
   changes) *and* make `update-status` self-heal for existing changes, or only one?
2. **Test harness** — is there an existing test runner for the `bin/` scripts, or do we add one?

_Resolved during review: B1 parked (out of scope); GitHub `specclaw-pr` B7 fix included in scope
(confirmed it shares the same `build_pr_title` bug as `specclaw-azdo-pr`)._

---

**To proceed:** Review this proposal and approve to begin planning.
