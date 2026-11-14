# Spike findings: how the PR review loop has worked in Project A

**Date:** 2026-10-16 · **Source:** Project A's review-records script (172 PRs, 538 rounds),
`.specclaw/changes/*/{status,learnings}.md`, git history. ADO threads were not readable (az auth), so the
qualitative sample relies on the fixing agent's own records. **Confidence: medium.**

## Quantitative (all 172 PRs with a metrics row)

| Round | PRs reaching it | Has ≥1 blocker/major | Mean majors | Mean minors |
|---|---|---|---|---|
| 1 | 172 | 83% | 3.26 | 7.73 |
| 2 | 124 | 45% | 0.95 | 2.77 |
| 3 | 83 | 35% | 0.86 | 2.10 |
| 4 | 56 | 36% | 0.66 | 2.16 |
| 5 | 32 | 44% | 0.59 | 2.22 |
| 6+ | 71 | 24% | 0.45 | 2.01 |

- 139 of 538 rounds (26%) ran *after* a round with 0 blocker/major; they found 34 of 853 b/M (4%).
- Median rounds per PR: PRs 160–219 → 1, 220–279 → 4, 280–399 → 3, 400–459 → 2. The lessons loop helped
  but has plateaued.
- ⅓ of branch commits are round records; each one re-triggers CI (~18 min) and the review.

## Qualitative (24 round-2+ blocker/major findings, 11 PRs, biased to long loops)

| Category | Count |
|---|---|
| FIX-INDUCED: the previous fix was incomplete or introduced a defect | 16 |
| MISSED-EARLIER: present at round 1, not flagged | 4 |
| SEVERITY-INFLATION: records, lint or wording rated major | 3 |
| FALSE-POSITIVE: a tool limit | 1 |
| SCOPE-CREEP | 0 |

**Main finding:** late rounds are mostly **real defects created by narrow fixes.** The fixer patches the case the
reviewer named, and the next round finds the next variant (one PR took four rounds on one text-matching rule; another took four rounds on one claim). Late rounds are not mainly reviewer churn.
**"Fix the class, not the case"** has been in Project A's pitfalls file since 2026-10-01, yet it recurred in 8+ PRs after
that: a prose lesson does not change behaviour. "Second copy of logic" rises from 4% of round-1 lessons to 12% of
later-round lessons, so fixes are creating the duplicates.

Other findings:
- **The stop rule is unsafe on its own:** 397 r6 found 3 real majors after a clean r5. All came from fixes that
  incremental rounds could not see. A final whole-PR pass catches what delta rounds miss.
- **Pre-push review:** about 95% of round-1 lessons were findable from the diff alone. But a single pre-PR review
  run samples a different subset (285: pre-check 4 majors, then r1 3), so one run does not replace the loop. It
  shortens it.
- **Duplicates:** the two passes (A and B) often file the same major twice, which inflates the counts.
- **Base-branch noise:** rounds that only see code merged from develop add rounds without adding signal.
- **Wall time per round** (fix + CI + review): 20–70 min typical, up to 1.5–3 h (one PR: ~31 h to clean).

## Implications for 044

1. The biggest lever is the **fix**, not the review. Make each fix prove the *class*: a table-driven variant test
   and a check of every caller. After 2 rounds on the same finding, escalate to a redesign or a human decision.
2. Pre-push self-review on each fix diff (same rubric) before pushing, so the server round is confirmation.
3. Delta rounds scoped to the PR's own delta plus its **impact set** (callers of changed symbols, earlier finding
   sites), excluding base-branch merges; plus **one final whole-PR pass**, instead of a blind stop rule.
4. Severity calibration: a round-2+ major needs a concrete failure scenario; records, process docs and lint
   are never major; dedupe passes by root cause.
5. Turn recurring lessons into guards (tests/lint), not prose. That is what memory is for.
