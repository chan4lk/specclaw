# Proposal: Sync — "review loop clean" PR status, release gate by severity, fast-track switch, CI template

**Created:** 2026-11-14
**Status:** ✅ Approved 2026-11-14
**Feature:** devloop
**Depends on:** none

## Problem

An agent approving its own PR is safe only when the approval rests on a recorded clean review, not on the agent
alone (ADR-0017 decision 59). Today nothing posts that record on the PR, so branch policy cannot require it.
Releases also have no rule for open debt: a queue that must be empty never empties, so the gate gets bypassed
(decision 58). And a project that trades review depth for speed has no switch for it and no list of what it
skipped (decision 57).

## Proposed Solution

1. **Clean-loop status:** after `specclaw-review verdict` exits 0 at HEAD, `specclaw-pr` / `pr-azdo` post a
   `specclaw/review-loop: clean` status on the PR's head (GitHub commit status / AzDO PR status), linking the
   final round file. Branch policy can then require it.
2. **Fast track:** `review.fast_track` in config (off by default; a list of changes or `all`). When on, one
   round, and only blockers in `release_gate.block_on` classes are fixed. Every other finding is appended to
   `.specclaw/debt.md` through the review writer, never by hand.
3. **Release gate:** `specclaw-sync release <base> <target>` lists every open `debt.md` and follow-up item
   in the range. It exits 1 only when an item's class is in `release_gate.block_on` (default: law, security,
   data-loss). Other debt is listed and released.
4. **CI template:** `specclaw-review`'s `ci/` templates gain the verdict, size-cap (060) and status steps.

## Scope

### In Scope
- Status posting for GitHub and AzDO; `fast_track` and `release_gate` config keys; `debt.md` writer; the
  `release` command; CI template steps; tests with stubbed `gh`/`az` calls

### Out of Scope
- Auto-approving or auto-merging PRs: branch policy stays the project's own
- Jira (no PR concept there)

## Impact

- **Size:** architectural — new config surface and a status contract that branch policies depend on
- **Files affected:** ~10
- **Complexity:** large
- **Risk:** medium. A status posted on the wrong head would approve unreviewed code. Post only when the
  verdict's final-pass head equals the PR's head.

## Open Questions

- Does the fast-track switch belong in `specclaw-review` (it changes the review loop) rather than in sync? Proposed: config in review, release command in sync.

---

**To proceed:** Review this proposal and approve to begin planning.
