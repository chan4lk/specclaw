# Code Review Report: numbered-change-folders

**Reviewed:** 2026-08-08
**Model:** claude-sonnet-4-6
**Verdict:** APPROVED_WITH_NOTES

## Summary

4 findings: 0 BLOCK, 2 WARN, 2 NOTE

## Findings

### [WARN] plugins/specclaw/tests/run-change-numbering-tests.sh:431 — Test quality

**Problem:** The AC6a-6 assertion uses the regex `^0[0-9][0-9]$` to check that `specclaw-next-change-number` returns a three-digit ordinal on this repository's real `.specclaw`. This regex only matches `001`–`099`. Once the repo accumulates 100 or more numbered changes (currently at ~32), the script will return `100` or higher, and this assertion will fire a false failure even though the script is working correctly. The comment says "the exact value moves with the repo, so only the invariant AC6a exists to protect is asserted" — but the invariant stated (not `2027`, not year-derived) is already covered by `AC6a-5`; `AC6a-6` adds a narrower, time-limited constraint.

### [WARN] plugins/specclaw/bin/specclaw-renumber-changes:335-337 — Correctness

**Problem:** The FR12 mid-build check uses substring matching against the current branch name and the full `git worktree list` output:
```bash
case "$CUR_BRANCH" in *"$name"*) BUSY+=("$name (checked-out branch ${CUR_BRANCH})"); continue ;; esac
case "$WORKTREES" in *"$name"*) BUSY+=("$name (live git worktree)") ;; esac
```
If a change named `foo` exists alongside a change named `foo-bar`, and the currently checked-out branch is `specclaw/foo-bar`, both `foo` and `foo-bar` would match `*"$name"*` — `foo` because `specclaw/foo-bar` contains `foo` as a substring. The refusal then names `foo` as mid-build when it is not. Similarly, the entire `git worktree list` output (which includes commit hashes and paths) is searched, so a commit hash or worktree path that contains a change name as a substring produces a false refusal. The consequence is conservative over-refusal (the rename does not happen), never silent corruption — so this is not a correctness bug in the destructive direction, but it violates the stated FR12 precondition and produces user-visible false alarms on repos with similarly-named changes.

### [NOTE] plugins/specclaw/bin/specclaw-renumber-changes:411-437 — YAGNI / Simplicity

**Problem:** The `refresh_state` function reads six fields from `state.json` and passes five of them as explicit arguments to `specclaw-set-phase`. The `branch` field is conspicuously absent from `refresh_state`'s local variables and from the `args=()` array — it is not passed via `--branch`. The design (FR15a) lists `branch` as one of the fields that must be round-tripped. The code is actually correct: `specclaw-set-phase` line 230 reads `branch` back from the existing `state.json` when no `--branch` flag is provided (`[ -n "$BRANCH" ] || BRANCH="$(state_field "$STATE_FILE" branch)"`), so the branch is preserved. But there is no comment in `refresh_state` explaining this delegation, and the AC13m test confirms correctness rather than the mechanism. A one-line comment — "branch is not passed; set-phase reads it from the file at line 230" — would prevent a future reader from concluding that branch is silently lost.

**Suggestion:** Add `# branch is not passed explicitly — set-phase reads it back from state.json` above the `"$SET_PHASE"` invocation on line 436.

### [NOTE] plugins/specclaw/bin/specclaw-update-status:184-185 / plugins/specclaw/bin/specclaw-reconcile:606-607 — Naming

**Problem:** Both files carry the comment "This function is duplicated verbatim in specclaw-update-status and specclaw-reconcile — keep the two byte-identical so a diff proves they agree." The duplication is justified (no sourcing convention between standalone executables, design decision 5 in design.md). The test `O0b` pins byte-identity. This is not a finding against the design. However, the word "verbatim" in the comment has historically been the introduction to drift: the comment says "verbatim" and "byte-identical", but a future editor who adjusts only one copy will see both warnings and probably discount them. The `O0b` test is the only enforcement. This is low severity — the test is good — but worth noting as the single control for an acknowledged duplication.

_(No further findings.)_

## Verdict Rationale

The change is well-engineered. All ten review dimensions were examined. **Correctness in bash** is strong: base-ten forcing (`10#`) is applied in every place where a disk-derived digit run enters arithmetic, the `printf '%03d'` minimum-width is correct, and the SIGPIPE from the `git log | head -n 1` pipeline is properly swallowed by `|| true`. The **FR5a rule** is implemented in four places (`scan_dir` in `next-change-number`, `is_numbered` in `renumber-changes`, and the two inline checks in `ordered_dir_names`) and all four are logically equivalent — verified by reading each expression and confirmed by the `O0b` byte-identity test for the two that are meant to be identical. **Destructive-operation safety** is solid: plan→validate→execute strictly holds, no filesystem write precedes the FR13 collision check, and FR11/FR13 exit codes prevent misleading "clean" re-runs. The **set-phase-is-the-only-writer invariant** is fully honoured: `refresh_state` correctly delegates to `set-phase` rather than editing `state.json`, and the `branch` field — which FR15a requires — is round-tripped via `set-phase`'s own fallback read (line 230 of `set-phase`), confirmed by the AC13m assertion. The **test suite** is behavioural throughout: AC4 fires real `008-a` fixtures against the live script, AC13r asserts byte-identity of the whole state record, and `O0b` mechanically enforces the byte-identical comment. The two WARN findings are a fragile test assertion that will become a false failure once the repo passes 99 numbered changes, and a substring-based FR12 check that can produce false refusals for similarly-named changes (over-refusal, never under-refusal). Neither is a correctness bug in the destructive direction. Zero BLOCK findings; APPROVED_WITH_NOTES.
