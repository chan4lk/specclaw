# Proposal: Review — lesson recall at plan/build, fix-proves-test, lesson promotion

**Created:** 2026-11-14
**Status:** ✅ Approved 2026-11-14
**Feature:** devloop
**Depends on:** 059-core-records-suggest

## Problem

`specclaw-review` shows past lessons only to the **reviewer** (`review_core.py` injects memory into the review
prompt). Builders never see them, so the same defect class comes back in round 1. In TBML, round-1 repeat rate
stayed at 91–94% until lessons reached builders (ADR-0017 decisions 17, 29). A fix is also not required to
prove itself, and a recurring class never becomes a rule.

## Proposed Solution

1. **Recall at plan/build:** a `UserPromptSubmit` + `PostToolUse(Skill)` hook in `specclaw-review`. When it sees
   `/specclaw:plan <change>` or `/specclaw:build <change>`, it calls `memory_query` for the change's files. It
   also reads the change's `lesson` lines from `timeline.jsonl` (059). It hands back the 3 closest lessons as
   `additionalContext`, phrased as yes/no checks. It never blocks, and a failed recall says so (TBML
   `plan-recall.py`).
2. **Fix proves test:** before a fix round, `specclaw-review run --since` checks that each blocker or major
   marked fixed came with a test that fails on the pre-fix commit and passes on HEAD (TBML
   `fix-proves-test.sh`). A fix with no such test keeps the finding open.
3. **Promotion:** `learn` proposes a rule for a fingerprint seen in 3+ changes. Today it uses 2+. The
   threshold moves to config, and approval stays human (`learn --apply`).
4. **Rule packs:** add `unneeded-code` (an unrequested abstraction, dead code, a speculative feature is a
   major) and the error-handling checklist (swallowed failures, timeouts, races, durable writes, idempotency)
   to `review-rules/base.md`.

## Scope

### In Scope
- The recall hook and its registration; the fix-proof check in `review_core.py`; the promotion threshold in
  config; the two rule additions; tests

### Out of Scope
- Generated "Do not repeat" blocks in area `CLAUDE.md` files (later, if recall is not enough)
- A dashboard view of lessons (062)

## Impact

- **Size:** bounded — extends `review_core.py`, the `learn` skill and the rules; adds one hook
- **Files affected:** ~7
- **Complexity:** medium
- **Risk:** low for recall (it never blocks). Medium for fix-proof: a project whose tests cannot run on the
  pre-fix commit needs a clear "could not prove" state, never a silent pass.

## Open Questions

- Fix-proof cost: re-running the tests on the pre-fix commit doubles the test time per fix round. Run only
  the tests the fix added?

---

**To proceed:** Review this proposal and approve to begin planning.
