# Spec: Clean-loop PR status, fast track, release gate by severity, CI template

**Change:** 064-sync-clean-status-release-gate
**Created:** 2026-11-14
**Status:** 🟢 Planned

## Overview

Post a `specclaw/review-loop` status on a PR only when a clean final review pass covered exactly the PR's
head commit, so branch policy can require it (ADR-0017 decision 59). Add a per-project fast-track switch that
defers everything except gate-class blockers into a written debt list (decisions 31, 38, 57), and a release
command that lists open debt in a range and blocks only on law, security and data-loss classes (decision 58).

Decided open question: `review.fast_track`, the class gate and the `debt.md` writer live in
`specclaw-review`. The `release` command lives in `specclaw-sync` (`specclaw-sync release`).

## Requirements

### Functional Requirements

- **FR-1 Head-bound verdict.** `specclaw-review verdict --change <c> --head <sha>` exits 0 only when the
  verdict is clean **and** `<sha>` is a full commit id that is either the final pass's head or a descendant
  whose commits since the final pass touch only `.specclaw/` paths (operator decision, 2026-11-14). A
  commit touching any other path, docs included, is a mismatch. On success it prints the final round file
  path on line 2.
- **FR-2 GitHub status.** After the PR exists, `specclaw-pr` reads the PR's current head SHA from GitHub and
  runs FR-1 against it. On exit 0 it posts one commit status on that SHA: context `specclaw/review-loop`,
  state `success`, description `clean`, target URL the final round file on the PR branch. On any other
  outcome it posts nothing and prints why. It never fails the script.
- **FR-3 AzDO status.** After the PR exists, `specclaw-azdo-pr` reads the PR's latest iteration and its
  source commit, runs FR-1 against that commit, and on exit 0 posts one PR status: `context.genre`
  `specclaw`, `context.name` `review-loop`, state `succeeded`, description `clean`, `iterationId` of that
  iteration. Otherwise nothing is posted. It never fails the script.
- **FR-4 Finding class.** The reviewer contract asks for `class`: `law | security | data-loss | other`.
  Calibration normalises it (lower case, `data loss`/`data_loss` → `data-loss`, unknown → `other`). Follow-up
  lines carry `class:<c>` in their trailing comment.
- **FR-5 Fast track.** `review.fast_track` (off by default) is a list of change names or `all`. For a covered
  change, every `run` is a final pass (whole change, final model): one round. Only `blocker` findings whose
  class is in `release_gate.block_on` make the round `open`. Every other finding is appended, deduplicated
  by fingerprint, to `.specclaw/debt.md` as an open `- [ ]` item, and not to `follow-ups.md`.
- **FR-6 Release gate config.** `release_gate.block_on` (top-level block) lists blocking classes. Default:
  `law, security, data-loss`.
- **FR-7 Release command.** `specclaw-sync release <base> <target>` lists every open item (a `- ` line that
  is not `- [x]`) in `.specclaw/debt.md` and every `.specclaw/changes/**/follow-ups.md` at `<target>` that is
  not present at `<base>`. It reads `release_gate.block_on` from `<target>`'s config. Exit 1 when any listed
  item's class is in `block_on`, 0 otherwise, 2 on a usage or git error.
- **FR-8 CI templates.** Both `ci/` templates check out the PR head commit, run the verdict, and post the
  status through FR-1's gate with the pipeline's own token.

### Non-Functional Requirements

- **NFR-1** No test calls GitHub or AzDO: `gh` and `curl` are stubbed on PATH.
- **NFR-2** No auto-approve, no auto-merge, no Jira.
- **NFR-3** Status posting is bookkeeping: any failure warns and the PR command still exits 0.

## Acceptance Criteria

- **AC-1** `verdict --head`: clean final at the given SHA → exit 0 and round file on line 2; a descendant
  reached by `.specclaw/`-only commits → exit 0; an unrelated SHA, a SHA prefix, a docs commit, or a commit
  touching one code file and one `.specclaw/` file → exit 1; a non-clean verdict → exit 1.
- **AC-2** `specclaw-pr` status step with stubbed `gh`: matching head → exactly one `statuses/<sha>` POST with
  context `specclaw/review-loop` and state `success`; mismatched head → no POST; open verdict → no POST;
  `specclaw-review` absent → no POST and exit 0.
- **AC-3** `specclaw-azdo-pr` status step with stubbed `curl`: matching iteration commit → exactly one
  `statuses` POST carrying `review-loop`, `succeeded` and the iteration id; mismatch → no POST.
- **AC-4** A finding with `"class":"Data Loss"` is stored as `data-loss`; a missing class is `other`; its
  follow-up line carries `class:`.
- **AC-5** Fast track on: one `run` records `final: true`; a security major and an `other` blocker give exit
  0 and land in `.specclaw/debt.md` (not `follow-ups.md`); a security blocker gives exit 1; a re-run does not
  duplicate debt lines. Fast track off: behaviour unchanged.
- **AC-6** `release`: a range adding only `other` debt exits 0 and lists it; adding a `security` item exits 1
  and marks it; a ticked `- [x]` item and an item already present at base are not listed; a `block_on` set to
  `[law]` in config makes the security item non-blocking; a bad ref exits 2.
- **AC-7** Both CI templates contain the verdict step and a status step gated by `verdict --head`.
- **AC-8** The new suites run in `.github/workflows/ci.yml`; all touched plugins' suites pass.

## Edge Cases

- PR head lookup fails (network, auth): no status, a warning, exit 0.
- The final round is clean but a later non-final round exists: the verdict is not clean, so no status.
- `debt.md` absent: the writer creates it with a header.
- Follow-up lines written before this change have no `class:`: the release command treats them as `other`.

## Assumptions

- First built with strict head equality, which meant the status never posted in the normal flow (round
  records and PR bookkeeping are committed after the final pass). The operator then approved allowing
  commits that touch only `.specclaw/` paths (2026-11-14). The plain verdict's drift rule is reused,
  narrowed to `.specclaw/`, because that rule also lets docs through.
- The PR-size step for the CI templates waits for change 060's command; it is not added here.
