# Design: Clean-loop PR status, fast track, release gate by severity, CI template

**Change:** 064-sync-clean-status-release-gate
**Created:** 2026-11-14

## Technical Approach

One safety gate, three consumers. The decision "may a clean status go on this SHA" lives in one tested
place, `specclaw-review verdict --head <sha>`. `specclaw-pr` (gh), `specclaw-azdo-pr` (curl, as it already
talks to AzDO) and the two CI templates only fetch the PR head, ask the gate, and post with their own
tooling. Mismatch means no call to the status API at all.

Fast track and the class gate are a small branch inside the existing round settlement in `review_core.py`;
the debt writer mirrors `append_follow_ups`. The release command is a new Python bin in `specclaw-sync`
that reads markdown from git objects, so it works in CI on any two refs without a checkout of either.

## Architecture

```
specclaw-review run ──► round-N.json (head, final, status, findings[class])
        │  fast_track? ──► final pass; gate = blocker ∧ class∈block_on; rest ──► .specclaw/debt.md
        ▼
specclaw-review verdict --head SHA ── exit 0 only if clean ∧ final head == SHA
        ▲                    ▲                         ▲
specclaw-pr (gh api)   specclaw-azdo-pr (curl)   ci/*.yml (gh api / curl)
        └── POST status only on exit 0

specclaw-sync release BASE TARGET ── git show {BASE,TARGET}:debt.md|follow-ups.md ── exit 1 iff class∈block_on
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw-review/lib/review_core.py` | modify | `class` in contract + calibration; `block_on`, `fast_track`, `append_debt`; fast-track settle; `verdict_at` |
| `plugins/specclaw-review/bin/specclaw-review` | modify | `verdict --head <sha>` |
| `plugins/specclaw-review/ci/github-actions.yml` | modify | PR-head checkout, verdict, gated status step |
| `plugins/specclaw-review/ci/azure-pipelines.yml` | modify | PR-head checkout, verdict, gated status step |
| `plugins/specclaw-review/skills/review/SKILL.md` | modify | fast track, debt, status, release gate |
| `plugins/specclaw-review/tests/run-review-tests.sh` | modify | AC-1, AC-4, AC-5, AC-7 |
| `plugins/specclaw/bin/specclaw-pr` | modify | `post_review_status` after bookkeeping |
| `plugins/specclaw/tests/run-review-status-tests.sh` | create | AC-2 with stubbed `gh` |
| `plugins/specclaw-sync/bin/specclaw-azdo-pr` | modify | `post_review_status` after bookkeeping |
| `plugins/specclaw-sync/bin/specclaw-sync` | create | `release <base> <target>` |
| `plugins/specclaw-sync/tests/run-azdo-review-status-tests.sh` | create | AC-3 with stubbed `curl` |
| `plugins/specclaw-sync/tests/run-release-tests.sh` | create | AC-6 |
| `.github/workflows/ci.yml` | modify | run the new suites |

## Data Model Changes

- Finding: new `class` field (`law | security | data-loss | other`).
- `.specclaw/debt.md` line: `- [ ] [<class> <severity> <rule>] \`file:line\` message (change <c>, round <n>) <!-- fp:<fp> class:<class> -->`.
- `follow-ups.md` comment gains `class:<class>`: `<!-- fp:<fp> class:<class> -->`.
- Config: `review.fast_track: [<change>...] | all`; top-level `release_gate: { block_on: [law, security, data-loss] }`.

## API Changes

- `specclaw-review verdict --change <c> --head <sha>`: new flag. Without it, output and exit codes are unchanged.
- `specclaw-sync release <base> <target>`: new command. Exit 0 / 1 (blocking debt) / 2 (usage, git).
- GitHub: `POST repos/{owner}/{repo}/statuses/{sha}`. AzDO: `POST git/repositories/{repo}/pullRequests/{id}/statuses?api-version=7.1` with `iterationId`.

## Key Decisions

1. **Strict head equality** (operator requirement). `--head` refuses the records-only drift the plain verdict
   accepts. Consequence: in the default `specclaw-pr` flow the post-PR bookkeeping commit moves the head, so
   no status posts there. Flagged in the PR for an operator decision; relaxing it is a one-line change in
   `verdict_at`.
2. **AzDO status bound to an iteration.** A PR status without `iterationId` survives later pushes; binding it
   to the iteration whose source commit was checked lets "reset on source update" policies drop it.
3. **Fast track = final pass.** "One round" is implemented by making each fast-track `run` a final pass, so
   the existing verdict needs no fast-track branch.
4. **Debt replaces follow-ups under fast track**, so one finding is never tracked twice.
5. **Release reads git objects** (`git show ref:path`), not the working tree, so base and target need no checkout.
6. **CI PR-size step deferred** to change 060, whose command does not exist on `main` yet.

## Risks & Mitigations

- *Status on the wrong head approves unreviewed code.* One gate, exact SHA compare, mismatch tests on both hosts.
- *A reviewer omits `class`.* Defaults to `other`: deferred, listed, non-blocking. A gate-class blocker the
  model mislabels is the residual risk; the full loop (fast track off) is unaffected.
- *Older follow-ups have no class.* Treated as `other`.
