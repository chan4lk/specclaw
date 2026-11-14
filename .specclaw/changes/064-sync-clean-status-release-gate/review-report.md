# Code Review Report: 064-sync-clean-status-release-gate

**Reviewed:** 2026-11-14
**Model:** claude-sonnet-5-5
**Verdict:** CHANGES_REQUESTED

## Summary

5 findings: 1 BLOCK, 2 WARN, 2 NOTE. Status-post safety contract holds on every path checked (see rationale).

## Findings

### [BLOCK] plugins/specclaw-review/lib/review_core.py:641 (and :629) — Correctness / Security
**Problem:** The model-supplied message is interpolated raw into a one-line list item whose class lives in a trailing comment:
`f"{f.get('message','')} (change {change}, round {round_no})"` then `line(f) + f" <!-- fp:{f['fp']} class:{f.get('class', 'other')} -->\n"`.
No newline flattening exists in `calibrate` or `_append_items`. A multi-line message puts the `class:` comment on a continuation line. In `specclaw-sync` `open_items` keeps only `- ` lines, and `CLASS_RE` runs per line, so the item gets class `other`. A security or data-loss debt item then fails open and does not block the release.
**Fix:** In `_append_items`, flatten first: `msg = " ".join(str(...).split())`. Do this in the shared writer so follow-ups and debt both get it. Add a test with a multi-line security message.

### [WARN] plugins/specclaw-review/lib/review_core.py:774 — Design adherence (unreachable status)
**Problem:** `if code == 0 and last.get("head") != sha:` is correct and strict, and the contract is kept. But the round's `head` is recorded at round start (`"head": head(cfg.root)`), and the round file itself must be committed (CI templates read `review/round-N.json` from the PR diff). So the PR head is always a descendant of the final pass head, and the status can never post for a real PR, in either `post_review_status` or the CI templates. Only the stubbed tests reach it. The spec Assumptions only mention the bookkeeping commit, not that the round file alone already guarantees a mismatch.
**Fix:** Report this to the operator as the strict-equality consequence. Define the intended equality, for example that the final pass head is the PR head's parent and the commit touches only the round file. Do not relax it silently.

### [WARN] plugins/specclaw-review/lib/review_core.py:669 — Correctness
**Problem:** In fast track, `block = [f for f in found if f["severity"] == "blocker" and f["class"] in cfg.block_on]` drops the `not f.get("pre_existing")` guard that `blocking()` has. A pre-existing gate-class blocker can now hold the round open, and the change cannot fix it. Also `cfg.block_on` returns `[]` for `block_on: []` (blocks nothing) while `specclaw-sync` `block_on()` returns the default. The two disagree on the same config.
**Fix:** Pick one behaviour for each and make both sides match.

### [NOTE] plugins/specclaw-review/lib/review_core.py:613 — Correctness
**Problem:** `new = [f for f in findings if f"fp:{f['fp']}" not in existing]` is substring dedup against the whole file, including ticked `- [x]` items. A fixed debt item that regresses is never re-listed.
**Suggestion:** Dedup only against open lines, or accept this and document it.

### [NOTE] plugins/specclaw-sync/bin/specclaw-sync:68 — Correctness
**Problem:** `git("ls-tree", "-r", "--name-only", target, "--", ".specclaw")` prints paths relative to cwd, while `show` uses root-relative `ref:path`. This misses items when run from a subdirectory.
**Suggestion:** Add `--full-name` and run `git -C $(git rev-parse --show-toplevel)`.

## Verdict Rationale

Safety contract (strict head equality): `verdict_at` returns 0 only when `verdict()` is clean (which requires `last.final`, so `last` is the final round) and `last["head"] == sha` exactly. A short or abbreviated sha fails closed. `specclaw-pr` reads `headRefOid` and posts on that same `$sha`. `specclaw-azdo-pr` takes the sha and iteration id from the same latest-iteration record. Both CI templates post on `pull_request.head.sha` / `SourceCommitId` after checking out that sha, and the AzDO template also re-checks that the latest iteration commit equals it. No path posts on a different SHA. The only issues there are the unreachable status (WARN) and the stale-run case, where a late-running job posts on an old sha, which is harmless because it is sha-bound. The release command logic and tests look sound, but the multi-line message bypass of the class gate is a fail-open in the safety gate and should be fixed before merge.
