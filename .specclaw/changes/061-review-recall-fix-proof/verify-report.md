# Verify: 061-review-recall-fix-proof

**Verdict:** PASS WITH FOLLOW-UPS (operator exit rule, 2026-11-14)

## Review loop

- Rounds 1–4 by earlier builders. Round 4 escalated on `3adff7cdffcb` and `6fc81ad5e3ab`.
- Operator-approved redesign, then round 5 (`--since 430401f`): fix proof `proven`, 2 new majors, both escalated on first sight (`7eb75e14e8ad`, `f49834c4ae63`). Both object to the approved design (FR-9 and FR-10), so they were not changed.
- Round 6 (`--final`, first attempt): `not_run`. The backend model refused the request.
- Round 7 (`--final`, second attempt): 4 majors, 3 escalated. Two were clear bugs and were fixed once:
  - `6b39fb09d912`: a renamed test file was dropped from the proof. Fixed with `--no-renames`.
  - `893d88fc11e3`: the recall hook read any OSError as a missing file. Fixed: only `FileNotFoundError` counts as missing.
  - Each fix has a test row. The renamed-test row fails without its fix.
- No more final passes, per the two-pass cap. The remaining majors (`f49834c4ae63`/`a9fd689163c9`, `7eb75e14e8ad`, `08cdf72c9175`) are in `follow-ups.md`.
- Neither `3adff7cdffcb` nor `6fc81ad5e3ab` came back.

## Requirements

- FR-9: a file is gone when `git cat-file -e HEAD:<file>` fails. Its finding is carried (`file renamed or deleted`) in every later round, in `warn` and `block`. Tests cover rename, rename plus edit, and delete, each in both modes, over two `--since` rounds. This also closes minor `154df5545a02`.
- FR-10: the line-level (±3) matching (`_fix_touched`, `covers`, `unproven`) is removed together with its tests. The proof is per round. In `block` mode, a not-proven round re-opens every blocker or major the reviewer closed, with the reason `fix not proven: <reason>`. A test shows that a re-reported finding is not doubled. In `warn` mode the round only records the note.
- The spec's FR-5, FR-9, FR-10 and AC-4 and the review skill are updated to match.

## Tests

- `plugins/specclaw-review/tests/run-review-tests.sh`: all pass (79 PASS lines; 46 on main).
- All 60 `plugins/*/tests/run-*.sh` suites ran in clean worktrees of HEAD and of `origin/main` (1c03b41). On both, 46 exit 0. The same 14 fail on both, with identical counts:
  - bf-status: 152/4
  - blueprint: 125/14
  - prototype byte-identity: 1/15
  - prototype gates: 25/4
  - prototype readiness-scope: 16/6
  - prototype stack-resolver: 41/1
  - prototype status-machine: 25/4
  - quality: 9 failed
  - replay-classification: 200/4
  - party: 280/1
  - change-numbering: 156/6
  - long-orchestration: 269/3
  - phase-state: 192/1
  - synth-agent: 9/1

## Version

`chore: bump version to 0.9.8` updates 12 plugin manifests (Claude and Codex) and the 6 entries in `.claude-plugin/marketplace.json`.
