# Spec: Review — lesson recall at plan/build, fix-proves-test, lesson promotion

**Change:** 061-review-recall-fix-proof
**Size:** bounded

## Requirements

- **FR-1 Recall hook.** `hooks/recall` runs on `UserPromptSubmit` and `PostToolUse` (matcher `Skill`). On a
  typed `/specclaw:plan <change>` or `/specclaw:build <change>`, or a Skill call of either, it prints
  `hookSpecificOutput.additionalContext` with at most `review.recall_k` (default 3) lessons, each phrased as a
  yes/no check. Anything else prints nothing. It always exits 0.
- **FR-2 Recall sources, in this order:** the change's own `lesson` lines in `timeline.jsonl` (059), newest
  first; then memory lessons whose files share a file, folder or top folder with the change's files (the
  `memory_query` ranking); then `lesson` lines of other changes that share at least two words with the
  change's proposal. The change's files are the paths named in its `tasks.md`, `spec.md` and `proposal.md`.
  The change is found from the event's `cwd` upwards.
- **FR-3 Recall never fails silently.** Any error prints `specclaw-review recall unavailable: <reason>` as the
  context. No lesson prints `specclaw-review recall: no past lessons for <change>`.
- **FR-4 Fix proof.** A `run --since` round whose previous round left blocker/major findings checks the fix:
  the test files added or changed since the pre-fix commit (`review.test_paths`, with defaults) run with
  `review.test_command` (`{files}` expands to them) in a clean checkout of the pre-fix commit, where they must
  fail, and in a clean checkout of HEAD, where they must pass. The pre-fix commit is the previous round's
  `head`, or the previous round's proof base when that round was not proven.
- **FR-5 Not proven keeps findings open.** Every other outcome is `not proven: <reason>`: no
  `test_command`, no changed test file, a checkout that fails, tests that pass on the pre-fix commit, tests
  that fail on HEAD, a timeout. The previous round's blocker/major findings are then carried into this round
  (`carried: true`), so the round is `open` (or `escalate`). The result is recorded as `fix_proof` in the round
  file, printed by the CLI and returned by `review_run`.
- **FR-6** A `--final` pass right after a not-proven round runs the same check, so a final pass cannot clear an
  unproven fix.
- **FR-7 Promotion.** `learn` proposes lessons seen `review.learn_threshold` (default 3) or more times. The
  review loop counts a lesson once per change. Apply stays `learn --apply`, a human step.
- **FR-8 Rules.** `review-rules/base.md` gains B11 (unneeded code is a major) and B12 (error-handling
  checklist).

## Acceptance Criteria

- **AC-1:** `/specclaw:plan <c>` and a Skill call `specclaw:build` with args `<c>` both return the lessons as
  yes/no checks, own-change first, memory next, capped at `recall_k`; other prompts return nothing.
- **AC-2:** A missing change returns `recall unavailable`, exit 0, valid JSON.
- **AC-3:** A since round with an open major and no `test_command` → `not proven`, the major carried, exit 1.
- **AC-4:** A test that fails on the pre-fix commit and passes on HEAD → `proven`, a clean round exits 0.
- **AC-5:** A test that passes on the pre-fix commit, or fails on HEAD, or no changed test → `not proven`
  with that reason.
- **AC-6:** After a not-proven round, a later test is checked against the first pre-fix commit; a `--final`
  pass after a not-proven round carries the findings.
- **AC-7:** `learn` lists a lesson seen in 3 changes, not one seen in 2; `learn_threshold: 2` lists it.
- **AC-8:** `rules` prints B11 and B12; `hooks.json` registers the recall hook; the existing suite passes.

## Approach

One decision: the fix proof is per round, not per finding. Tests cannot be mapped to findings in a
project-neutral way, so the round's changed tests prove the round's fixes as a whole, in two clean worktrees
(pre-fix, HEAD), so only the source differs between the runs.

File map:
- `plugins/specclaw-review/lib/review_core.py` (fix proof, carry, threshold), `lib/review_memory.py` (relevance)
- `plugins/specclaw-review/hooks/recall` (new), `hooks/hooks.json`; `bin/specclaw-review`, `mcp/server.py`
- `plugins/specclaw-review/review-rules/base.md`; `skills/review/SKILL.md`, `skills/learn/SKILL.md`
- `plugins/specclaw-review/tests/run-review-tests.sh`
