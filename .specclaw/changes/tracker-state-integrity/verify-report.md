# Verify Report: tracker-state-integrity

**Branch:** `specclaw/tracker-state-integrity` (8 commits on top of `6eaf7ee`)
**Date:** 2026-08-01
**Spec:** `.specclaw/changes/tracker-state-integrity/spec.md` — 9 FRs, 5 NFRs, 12 ACs, 10 edge cases

## Evidence base

Three independent sources, in decreasing order of weight:

1. **`bash plugins/specclaw/tests/run-phase-state-tests.sh` — `PASS: 193   FAIL: 0`.** Every
   assertion in the suite was read, not just the summary line. The suite is hermetic: `mktemp -d`
   workdir, three separate `.specclaw` trees, `gh` reached only through PATH shims (absent /
   failing / answering), and a closing assertion that no `state.json` was written outside the temp
   dir.
2. **Reproductions in scratch `mktemp -d` trees** for the ACs the suite did not originally cover
   (AC5, AC6, AC7, AC8, AC11 and edge cases 1/2/7). AC5–AC7 have since been folded into the suite
   as the `S1`–`S4` cases — see *Remediation* below.
3. **Code reading** of `specclaw-set-phase`, `specclaw-reconcile`, `specclaw-update-status`, and
   the diffs to `specclaw-build`, `specclaw-pr`, `specclaw-azdo-pr`, `specclaw-verify`, the three
   SKILL.md files, `ci.yml` and `shellcheck-gate.sh`.

**Discounted as evidence:** `.specclaw/config.yaml` configures no `build.test_command` /
`lint_command` / `build_command`, so the collected `tests_passed / lint_passed / build_passed:
true` are vacuously true and carry no weight. Nothing here rests on them.

**`.specclaw/context.md` does not exist** in this repo, so there were no project-level coding rules
to check the implementation against.

---

## Per-criterion findings

### AC1 — MET
`set-phase … build done` on a change with no `state.json` creates valid JSON with `phase: "build"`
and a `phases.build` record.

Suite AC1a–AC1j assert, on a change directory containing only `status.md`: exit 0; the file exists;
it parses; `.change`, `.phase`, `.phases.build.status`, `.phases.build.tasks == {"done":7,
"total":11,"failed":0}`; `.phases.build.at` matches `^[0-9]{4}-…Z$`; `.phases.verify` is empty (no
spurious records); and the Build row landed in `status.md` as `| Build | ✅ Done | 7/11 tasks |`.

Atomicity (FR1) is structural: `specclaw-set-phase` builds into a `mktemp` **inside the change
directory** (same-filesystem rename), validates that the temp file parses, and only then `mv`s. A
`trap 'rm -f "$tmpfile"' EXIT` covers every `die` path.

### AC2 — MET
Running the identical command twice leaves both files byte-identical and exits 0 both times.

Suite AC2a–AC2d snapshot both files after run 1 and `cmp -s` them after run 2 — a real byte
comparison, not a field-by-field one.

The mechanism is the non-obvious part: `set-phase` reads back the existing `phases.<phase>` record,
rebuilds it with the *old* `at`, and reuses that timestamp when the rebuilt record is identical.
Without it, a second run one second later would churn the timestamp and break AC2. Idempotency is
also pinned under the jq-less reader (FBi–FBk) and for a table-less `status.md` (E5f/E5g).

### AC3 — MET
`build done` on a change already at `phase: "pr"` exits non-zero, changes nothing, names both
phases; `--force` succeeds.

Suite AC3a–AC3k: exit 3; stderr contains `'pr'`, `'build'` and `--force`; and `assert_same_file` on
**both** files against pre-call snapshots. "Changes nothing" is structural too — the rank check runs
before `mktemp` is ever called, so there is no temp file to leak. AC3j/AC3k confirm the superseded
`pr` record and its `url` survive the forced backwards move rather than being dropped.

### AC4 — MET
After `set-phase … pr raised --url U`, exactly one `| PR |` row carries `U`, and the `GitHub Issue`
line is unmodified.

Suite AC4a–AC4h: `grep -c '^| PR |'` is exactly `1`; the row reads `| PR | ✅ Raised | <URL> |`; the
`**GitHub Issue:**` line is compared byte-for-byte against a pre-capture *and* asserted still to be
the file's last line; the `| Verify |` row is untouched.

The suite goes past what AC4 requires and pins a real defect (D3): the PR row must land inside the
Progress table, not in the second table under `## Agent Runs`. `AC4f` compares line numbers, `AC4g`
asserts the PR row directly follows the last Progress row, `AC4h` asserts the Agent Runs row count
is unchanged, and E4f/E4g repeat it against the shipped `templates/status.md`. This is the concrete
NFR1 guarantee — `specclaw-gh-sync`, `specclaw-jira-issue` and `specclaw-azdo-issue` all grep those
lines.

Edge case 9 is covered by E9b/E9c: a URL containing literal pipes, brackets and a backslash lands
intact in both files, and the Progress table's row set stays exactly
`Proposal Spec Design Tasks Build Verify PR`.

### AC5 — MET
A `state.json` recording `phase: "pr"` renders as PR-in-review with `gh` unavailable.

Originally proved by hand; **now pinned in the suite** as `S1a`–`S1f`, which run
`specclaw-update-status` under the no-`gh` shim with `SPECCLAW_STATUS_NO_PR=1` and assert the exact
line:

```
- 🔀 **recorded** — pr raised | 2/2 tasks (100%) | 0 failed
```

plus exit 0, empty stderr (no network call is possible — there is no `gh` on that PATH), and
`assert_lacks "✅ **recorded**"`. Under the pre-change implementation the same inputs render
`✅ **recorded** — 2/2 tasks (100%)`, indistinguishable from "build finished" — the exact bug this
change exists to kill.

*Resolved since first verify:* `phase_render` used to read `phases.pr.state`, a field
`specclaw-set-phase` never writes, making FR6's illustrative `🔀 pr open` unreachable. The dead read
is gone; the qualifier is `phases.pr.status` (`raised | merged | closed`), and `S1e`/`S1f` pin both
halves of that fact.

### AC6 — MET
A change with no `state.json` renders byte-identically to the previous implementation.

Proved by A/B against the actual old binary: `6eaf7ee` checked out into a git worktree, both
versions of `specclaw-update-status` run over identical fixture trees (a partial change, one with a
failed task, a proposal-only change, plus an archived change) with `SPECCLAW_STATUS_NO_PR=1` →
`BYTE-IDENTICAL`, modulo the `**Last Updated:**` wall-clock line both versions generate from the
same unchanged `date` call. Stderr was empty: a merely-absent `state.json` is not a fault and emits
no warning.

**Now pinned in the suite** as `S2a`–`S2c`, which assert the inferred line
`- 🔨 **unmanaged** — 1/2 tasks (50%) | 0 failed` and empty stderr, so a future regression fails CI
rather than waiting for someone to re-run the A/B by hand.

### AC7 — MET
A corrupt `state.json` renders via fallback, exits 0, warns on stderr.

**Now pinned in the suite** as `S3a`–`S3f`, both corruption shapes:

- truncated (`{"change":"corrupt","phase":"pr","phas`) → rc 0, stderr
  `unreadable state.json for corrupt; falling back to task inference`, rendered
  `- 🔨 **corrupt** — 1/2 tasks (50%) | 0 failed` — the checkbox inference, not the `pr` the corrupt
  file half-claims (`S3d` asserts `🔀 **corrupt**` never appears);
- not JSON at all (`garbage not json`) → identical rc, warning and rendering.

The writer side is equally fail-open: FR7a/FR7c confirm a truncated `state.json` does not *block* a
transition, and FR7d confirms the unreadable record is not copied forward into the rewritten file.

### AC8 — MET
`specclaw-build` writes the actual branch; a change whose branch does not match `git.branch_prefix`
still resolves its PR.

Reproduced end-to-end in a throwaway git repo: config declared `branch_prefix: "specclaw/"`, the
checked-out branch was `feature/totally-different-name`. `specclaw-build setup` wrote
`"branch": "feature/totally-different-name"`. Then, with a `gh` shim answering only for
`--head feature/totally-different-name`:

| condition | rendered line |
|---|---|
| `state.json` present | `🔨 **alpha** — build in-progress \| 2/2 tasks (100%) \| 0 failed \| **PR #99 open**` |
| `state.json` removed (old prefix-guess path) | `✅ **alpha** — 2/2 tasks (100%)` — **PR invisible** |

A direct A/B on one tree and one shim: the recorded branch resolves the PR, the
`${branch_prefix}${change}` guess does not. `specclaw-build` asks `git branch --show-current` and
falls back to the computed name only when git cannot answer (detached HEAD). The reconcile side is
pinned independently by R7c, which asserts the drift message names `on 'feature/odd-name'`.

### AC9 — MET
`reconcile` on a change recorded at `build` with a complete `tasks.md` and a `verify-report.md`
reports drift and exits non-zero; `--fix` advances and exits 0.

Suite AC9a–AC9m: non-zero exit; the message `state.json says 'build'; observation supports
'verify'`; the stale counts alongside the observed ones; and `assert_same_file` proving **report
mode wrote nothing**. Then `--fix` → exit 0, `.phase == "verify"`, `.phases.verify.verdict ==
"PASS"` adopted from `verify-report.md`, `.phases.build.tasks` refreshed to `4/4/0`.

AC9j/AC9k are the load-bearing pair: they assert `status.md`'s Verify *and* Build rows were
rewritten. `specclaw-reconcile` never touches `status.md` itself, so those rows can only have moved
if `--fix` genuinely routed through `specclaw-set-phase` — the FR2 single-writer invariant proved by
observation rather than assumed. AC9l/AC9m re-run the audit and confirm idempotency.

### AC10 — MET
`reconcile --fix` with `gh` unavailable reports the PR dimension as `unknown`, does not clear a
recorded PR, and says what it skipped.

Suite AC10a–AC10s plus R5 and R6. What makes this trustworthy is that the three `gh` states are
three real PATHs, not three mocks:

- **gh absent** (AC10a–AC10m): report mode exits 0 — an unobservable dimension is not drift — prints
  `pr       unknown` and `gh is not installed`, and `assert_lacks` proves `gh finds no PR` never
  appears. `--fix` exits 0, prints `SKIP     pr` and `never clears a recorded PR`, and
  `assert_same_file` proves both files are byte-identical afterwards.
- **gh present but failing, exit 4** (R5a–R5f): must read *identically* to gh being absent, else an
  unauthenticated laptop clears every PR it cannot see. Confirmed.
- **gh succeeding and finding nothing** (R6a–R6g): a real observation, so it *is* drift — but `--fix`
  still refuses, because adopting it means `pr → verify`, a downgrade. It prints
  `clearing a recorded PR is a downgrade` and, critically, `finding(s) found, none applied`, so a
  zero exit cannot be misread as clean.

AC10n–AC10s prove the mixed case: observable drift alongside an unknown still exits non-zero, and
`--fix` adopts the observable dimensions while still skipping the unknown and inventing no `pr`
record.

### AC11 — MET
`save_pr_url` failing internally does not abort `specclaw-pr` after `gh pr create` succeeded; the URL
is still reported and a warning printed.

Reproduced with three failure injections, running the real `record_pr_phase` + `save_pr_url` bodies
extracted verbatim from `specclaw-pr` under the same `set -euo pipefail`:

| case | injection | result |
|---|---|---|
| A | `specclaw-set-phase` stub exits 9 | warning printed, execution continued, `status.md` still got `**Status:** pr-raised` and the URL |
| B | set-phase exits 9 **and** the change dir + `status.md` made read-only | four separate warnings, no abort, continued |
| C | `specclaw-set-phase` binary removed, no `status.md` | warning, continued, minimal `status.md` written with the URL |

All three returned rc 0 and reached the line after `save_pr_url`. Case B is the adversarial one:
every writable-path operation failed and the function still returned 0. The URL reaches the user
regardless — `specclaw-pr` echoes `✅ PR created: $pr_url` after the bookkeeping block, and the call
site carries a belt-and-braces `|| warn` on top of a function that cannot return non-zero. The same
shape is mirrored in `specclaw-azdo-pr`, `specclaw-build`'s `record_phase`, and `specclaw-verify`'s
`cmd_update_status`.

### AC12 — PARTIAL
`shellcheck-gate.sh` passes: **verified.** The suite running green *in CI*: **unobserved.**

- `PATH=/tmp/shellcheck-v0.10.0:$PATH bash plugins/specclaw/tests/shellcheck-gate.sh` →
  `shellcheck: no new findings (25 known, all in the baseline)`, exit 0.
- The two new scripts are genuinely linted, not merely absent from the run: `shellcheck -f gcc` over
  both returns rc 0 with **zero output**, and neither appears in `shellcheck-baseline.txt` — nothing
  was silenced by baseline-padding. The baseline in fact *shrank* by two entries
  (`specclaw-verify SC2034`, `SC2155`), which the gate's own fixed-findings check would have flagged
  had they not genuinely gone.
- The gate itself got a correctness fix on this branch: `comm` now runs under `LC_ALL=C`, matching
  the collation its inputs were sorted with. Without it, `specclaw-verify SC2034` and
  `specclaw-verify-context SC2016` collate differently and `comm` reports the same pair as both
  fixed and new. A real latent bug, not a workaround.
- `.github/workflows/ci.yml` registers `Run phase-state tests` in the parser job, positioned **after**
  the `Install jq` step, so CI exercises the jq reader path while the suite's shims force the python3
  path in parallel.
- **What cannot be verified from here:** whether that CI job has actually run green. The suite is
  hermetic (no network, `gh` only via shims, `mktemp -d` workdir, asserted no writes outside it),
  passes 193/193 locally, and needs nothing the runner lacks — but the run itself is unobserved.

PARTIAL strictly on observability, not on suspicion.

---

## Other requirements checked

**FR5 (every lifecycle phase routes through `set-phase`)** — MET. `propose/SKILL.md` on approval,
`plan/SKILL.md` once per artifact, `archive/SKILL.md` before the move (so state travels with the
directory), `specclaw-build` at setup (with `--branch`) and at finalize (with `--tasks` derived from
`tasks.md`, flipping to `failed` when any gate or task failed), `specclaw-verify`'s
`cmd_update_status` (~50 lines of hand-rolled table surgery deleted, replaced by a delegated call),
and both PR scripts. The Build row no longer depends on a model remembering to edit prose.

**Edge cases** — all ten accounted for. 1 and 2 reproduced by hand; 3 (concurrent writers)
documented in the header — temp-file + `mv` means the loser's write is lost, never a corrupt file,
as the spec directs; 4, 5, 6, 8, 9, 10 pinned by suite cases E4–E10; 7 pinned twice, by R10a–R10d
for `reconcile` and `S4a`/`S4b` for the renderer.

**NFR2 (dependencies)** — MET, and better than required. `state.json` reads use jq when installed
and fall back to python3, requiring neither. The suite forces the fallback with a synthetic PATH,
asserts the shim really has no jq, then re-runs the write, the monotonicity check, the record
carry-forward and the idempotency check under it. The entire `reconcile` and renderer sections also
run jq-less. No jq version floor is imposed.

**NFR4 (test style)** — MET. Plain bash + coreutils, `pass`/`fail` counters, `mktemp -d`, non-zero
exit on failure. Matches `run-status-row-tests.sh`. Not bats.

**Version bump** — done: `0.6.2 → 0.6.3` in both `plugins/specclaw/.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json`, in sync.

**Documentation** — `plugins/specclaw/CLAUDE.md` gains a "Phase state: `specclaw-set-phase` is the
only writer" section stating the invariant, the rank order, the `--force` rule, `reconcile`'s audit
contract, and the reason it exists. The new suite is added to the suites table.

---

## Remediation applied after the first verify pass

Four findings from the first verify + code-review pass were fixed on this branch rather than
deferred:

1. **`specclaw-set-phase` sed injection** — the change name was interpolated unescaped into a `sed`
   *replacement*, where `&` means "the whole match" and `/` closes the expression. A change named
   `a&b` self-healed its `status.md` title to the literal `a{{title}}b`; one named `a/b` aborted the
   run after `state.json` was already written. Now escaped, and pinned by `E11a`–`E11d` — verified
   non-tautological: the old expression demonstrably produces `a{{title}}b`.
2. **Empty-timestamp guard** — without `set -e`, a failed `date` left `AT` empty and the record
   shipped `"at": ""`, which reads as "never happened". Now an explicit `die`.
3. **Dead read `phases.pr.state`** — removed from `specclaw-update-status`, with a comment recording
   that `phases.pr.status` is the field that carries the PR's disposition. `S1e`/`S1f` pin it.
4. **Untested renderer** — AC5, AC6 and AC7 were spec acceptance criteria with zero assertions; the
   suite never invoked `specclaw-update-status` at all. Now covered by `S1`–`S4` (17 assertions).
   This was the largest gap: three ACs were resting entirely on hand proofs that do not run in CI.

The absent `set -e` in both new scripts (a code-review NOTE) was kept and now carries a comment
explaining why: every state read is deliberately fail-open, and under `-e` a non-zero `jq` on a
malformed file would abort the very transition it is meant to permit.

Suite went 172 → 193 assertions, all green. `shellcheck-gate.sh`, `run-status-row-tests.sh`,
`run-long-orchestration-tests.sh` and `run-shellcheck-gate-tests.sh` re-run green afterwards.

---

## Note on the pre-existing parser-suite failures

`run-parser-tests.sh` reports `30 passed, 11 failed` locally. The jq diagnosis was confirmed, not
assumed, three ways: `command -v jq` finds nothing here; every one of the 11 failing assertions
routes through a `jq` invocation while the passing ones are the file's own "jq-free" cases; and,
decisively, the merge base `6eaf7ee` checked out into a worktree produces the identical
`30 passed, 11 failed`. `git diff --name-only 6eaf7ee..HEAD` touches no parser file. Environmental
and pre-existing, not a regression. CI installs jq.

---

## Verdict

PARTIAL

Eleven of twelve acceptance criteria are met on hard evidence: 193/193 assertions in a suite whose
every assertion was read, plus independent reproductions for AC8 and AC11 and an A/B of the new
renderer against the old binary checked out at the merge base for AC6. AC12 is PARTIAL on
observability alone — the shellcheck gate passes with zero findings against both new scripts and no
baseline padding, and the suite step is correctly registered in `ci.yml` after `Install jq`, but a
CI run cannot be observed from this environment. Every substantive defect found by the first verify
and code-review pass has been fixed on this branch and pinned by a test.

## Gaps

1. **AC12, CI half — unverified, not failed.** Confirm on the PR's first CI run. Verified proxies:
   the step exists in `ci.yml` after `Install jq`; the suite is hermetic and passes 193/193 locally.

2. **NFR1 tested for GitHub only.** AC4d/AC4d2 pin the `**GitHub Issue:**` line byte-for-byte, and
   `specclaw-status-row`'s awk touches only the matched label row, so the Jira and ADO Work Item
   lines are covered by the same mechanism — but no assertion exercises them directly. Low risk,
   zero coverage.

3. **`--tasks 0/0/0` is accepted.** `set-phase` validates the shape `^[0-9]+/[0-9]+/[0-9]+$` but not
   the arithmetic: `--tasks 9/3/0` (done > total) would be recorded and rendered as-is. No AC
   requires the check and no caller can currently produce such input — `specclaw-build` derives all
   three from one file. A note, not a defect.

4. **Duplicated `state_field` helper** across `set-phase`, `reconcile` and `update-status`, with no
   mechanical sync check (code-review WARN 4). The risk is a future fix landing in one copy only.
   Left as-is: extracting a shared library for three ~8-line readers is the larger change, and the
   plugin has no `lib/` convention yet.

5. **`reconcile <specclaw> archive/<name>`** reaches an archived change through the positional
   argument, bypassing the `archive` guard that the directory sweep applies (code-review NOTE 5).
   Requires deliberately typing the archive path; harmless (it audits, and `--fix` routes through
   `set-phase` as usual).

6. **Pre-existing, out of scope:** `run-parser-tests.sh` fails 11/41 locally for want of `jq`.
   Identical at the merge base; this branch touches no parser file. CI installs jq.

**Code Review:** APPROVED_WITH_NOTES — 7 findings: 0 BLOCK, 4 WARN, 3 NOTE. All four WARNs are
addressed above (three fixed, one — the duplicated helper — consciously deferred with a rationale).
