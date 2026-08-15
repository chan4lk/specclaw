# Verify Report: numbered-change-folders

**Change:** numbered-change-folders
**Branch:** `specclaw/numbered-change-folders`
**HEAD:** `af180fd`
**Verified:** 2026-08-08

## Verdict

PASS

Every acceptance criterion AC1–AC20 (including AC6a and AC6b) is MET. Each mechanically
checkable criterion was re-run independently against throwaway fixtures in `/tmp` and against
a sandbox clone of this repository, not taken from the build's test suite. The suite's own
result (160/160) was reproduced but is not the basis of any verdict below.

## Method

- Fixtures built by hand under `/tmp` (removed afterwards); none of them reused the project's
  test helpers.
- A full clone of this repo at this branch was checked out under `/tmp/vrepo` on a branch named
  `sandbox` (so FR12's checked-out-branch refusal would not mask the run) and the backfill was
  applied to it end to end, including a before/after `find -printf '%p %s %T@'` tree snapshot.
- The repository's own `.specclaw` was only ever read. `git status --porcelain -- .specclaw` is
  unchanged from the pre-verification snapshot apart from this report.
- `shellcheck` 0.9.0 was fetched with `apt-get download` + `dpkg-deb -x` into `/tmp`, used, and
  deleted.

## Acceptance criteria

| AC | Status | Evidence |
|----|--------|----------|
| AC1 | MET | Fixture with `.specclaw/changes/` empty: `specclaw-next-change-number` printed `001`, rc=0, stderr empty. |
| AC2 | MET | `changes/001-a/` + `changes/archive/007-b/` → `008`. Archive is scanned; the gap `002`–`006` is preserved. |
| AC3 | MET | Fixture with only `foo-bar/` and `baz/` → `001`, rc=0, stderr empty. |
| AC4 | MET | `changes/008-a/` → `009`, rc=0, **stderr empty** (no `value too great for base` error). Extended: `08-x`→`009`, `09-x`→`010`, `0008-x`→`009`, `0000008-x`→`009`, all with clean stderr. |
| AC5 | MET | `changes/999-a/` → `1000`. Width widens, no truncation or wrap. |
| AC6 | MET | Fixture with both `changes/archive/` (empty reserved dir) and `changes/archive-cleanup/` → `001`, rc=0. `archive` skipped by string equality, `archive-cleanup` treated as an ordinary unnumbered change. |
| AC6a | MET | `changes/archive/2026-07-22-build-engine/` alone → `001`, not `2027`. Against this repository's real `.specclaw` (read-only): `001` before the backfill. After `--apply` on the `/tmp/vrepo` clone (31 folders numbered `001`–`031`): `032`. Never `2027`, never `031`. |
| AC6b | MET | `changes/2026-some-slug/` → `2027`. The FR5a exclusion fires only on the full `YYYY-MM-DD` shape. |
| AC7 | MET | Dry run on the 31-folder clone printed all 31 `old → new` lines plus the summary, rc=0. `find .specclaw -printf '%p %s %T@'` before vs after: **identical** (193 entries, byte-for-byte, mtimes included). `git status --porcelain` empty. |
| AC8 | MET | Fixture `aaa`(2026-05-03), `bbb`(2026-05-01), `ccc`(2026-05-02) → `001-bbb`, `002-ccc`, `003-aaa`. Date order, not name order. |
| AC9 | MET | Fixture with `early`(06-05), `nocreated`(no `proposal.md` at all), `late`(06-20) in a git repo whose single commit is dated 06-10 → `001-early`, `002-nocreated`, `003-late`. Git-first-commit fallback placed it correctly; run exited 0. A second fixture with no proposal *and* no git repo fell through to `NO_DATE` and sorted last without crashing. |
| AC10 | MET | Three folders sharing `**Created:** 2026-04-04` → `001-alpha`, `002-mid`, `003-zeta` on three consecutive runs; `diff` of the three outputs identical. |
| AC11 | MET | Fixture with `008-existing/`, `zzz/`, `mmm/`: `--apply` exited **3** with the explanatory message (`008-existing (number 8)` — base ten, no octal error), and `find` before/after confirmed **nothing was renamed**. The same fixture with `--force --apply` produced `001-zzz`, `002-existing`, `003-mmm` — restarted from `001` in date order, ordinal prefix stripped rather than doubled. |
| AC12 | MET | Fixture where planned target `changes/002-bbb` already existed: exited **5** with `aborting before any rename`, and `find` before/after identical — no folder moved. |
| AC13 | MET | Real data (`/tmp/vrepo`, `030-tracker-state-integrity`): `python3 -m json` normalised diff of `state.json` before vs after shows **exactly one changed line**, `"change"`. `verdict: PASS`, `url`, `branch`, and both `at` timestamps (`2026-08-01T13:20:44Z`, `2026-08-01T13:24:51Z`) all preserved verbatim. Synthetic fixture carrying `tasks:{done:11,total:11,failed:0}` + `verdict` + `url` + `branch` in the current phase: same result — only `change` differs, `at` unchanged, so `set-phase` recognised the record as byte-identical and did not restamp it. All resulting files parse as JSON. |
| AC14 | MET | Clean fixture (`beta` at phase `build`, branch `specclaw/beta` present, 2/2 tasks): `specclaw-reconcile` reported `with drift: 0`, rc=0 **before** the rename and `with drift: 0`, rc=0 **after** it. On the real-data clone the one reported drift (`branch specclaw/tracker-state-integrity does not exist`) was reproduced identically on a *pristine* second clone before any rename — a clone artifact, not introduced by the backfill. |
| AC15 | MET | `changes/001-a/` + `changes/002-b/` → `specclaw-next-change-number` prints `003`. `skills/propose/SKILL.md` step 1 now instructs running `specclaw-next-change-number .specclaw`, joining it to the slug, and forbids hand-formatting; step 2 creates `.specclaw/changes/<change-name>/` and step 3 generates both `proposal.md` and `status.md` from templates. No other skill or script creates a change folder (grepped `skills/` and `bin/`). |
| AC16 | MET | `skills/archive/SKILL.md` step 4 now reads `.specclaw/changes/archive/<change>/` — "the name is preserved verbatim, number included, with no date prefix"; the front-matter description was updated to match. No remaining date-prefix instruction anywhere in `skills/`, `agents/`, `bin/`, `templates/`, `docs/`, or `README.md` (the only `archive/YYYY-` hits left are fixture data in test suites). Mechanically simulated: `set-phase … archived done` + `mv` to `changes/archive/003-foo/` → `STATUS.md` lists `✅ 003-foo`, `state.json` keeps `"change": "003-foo"`, and `next-change-number` then returns `004` (the archived number still counts). |
| AC17 | MET | Fixture `010-a`, `002-b`, `unnumbered-c` → `STATUS.md` Active list reads `002-b`, `010-a`, `unnumbered-c`. Numeric, not lexical; unnumbered last. |
| AC18 | MET | Same fixture: stdout and `STATUS.md` line 6 both carry `1 unnumbered change · run /specclaw:renumber to order them` (count correct, singular/plural handled). After renaming `unnumbered-c` → `003-c`, `grep -i 'unnumbered\|renumber' STATUS.md` returns **nothing at all**, and stdout carries no hint. |
| AC19 | MET | `shellcheck` 0.9.0 installed into `/tmp`; `bash plugins/specclaw/tests/shellcheck-gate.sh` → `no new findings (25 known, all in the baseline)`, rc=0. `md5sum` of `shellcheck-baseline.txt` identical before and after; `git diff main...HEAD -- shellcheck-baseline.txt` is empty. Direct `shellcheck -s bash` on `specclaw-next-change-number`, `specclaw-renumber-changes`, and `run-change-numbering-tests.sh` → rc=0, zero findings. |
| AC20 | MET | `.github/workflows/ci.yml:30-31` adds `Run change-numbering tests → bash plugins/specclaw/tests/run-change-numbering-tests.sh`. Local run: **160 passed, 0 failed**, rc=0. Full suite sweep below. |

## Targeted checks requested

### FR5a applied identically in all four consumers

Verified. All four sites use the same pair of patterns, `^[0-9]+-` and the exclusion
`^[0-9]{4}-[0-9]{2}-[0-9]{2}`:

- `bin/specclaw-next-change-number:95,106`
- `bin/specclaw-renumber-changes:138-145` (`is_numbered()`)
- `bin/specclaw-update-status:191` (`ordered_dir_names`) and `:226`, `:306` (the FR17 counters)
- `bin/specclaw-reconcile:613` (`ordered_dir_names`)

Behavioural cross-check rather than textual: the same three names were fed to every consumer.
`2026-07-22-legacy` is unnumbered everywhere (does not raise `next-change-number`'s maximum, does
not trip `renumber`'s FR11 refusal, sorts into the unnumbered group in `STATUS.md`);
`2026-some-slug` is numbered everywhere (yields `2027`, sorts in the numbered group at position
2026); `archive-cleanup` is an ordinary unnumbered change everywhere. No divergence found. The
suite additionally asserts the two `ordered_dir_names` copies are byte-identical, which I
confirmed by reading both.

One narrow, harmless asymmetry worth recording: `slug_of()` strips the legacy prefix with
`^[0-9]{4}-[0-9]{2}-[0-9]{2}-(.+)$` (trailing hyphen plus non-empty tail), while the classifier
omits the trailing hyphen. A folder named exactly `2026-07-22` with no slug would therefore be
classified unnumbered but renamed to `001-2026-07-22` rather than having the prefix removed. No
requirement covers a slugless folder and no such folder exists; noting for completeness only.

### The octal trap

Complete, not partial. Only two sites evaluate a disk-derived digit run and both force base ten:
`next-change-number:108-109` (`$((10#$n))` on both sides of the comparison) and
`renumber-changes:313` (the FR11 report). `renumber-changes`' own ordinal counter starts at 0 in
process and never reads a prefix. Exercised with `08-`, `09-`, `0008-`, `0000008-` prefixes
through both scripts, checking **stderr** and not just exit status: all clean, no
`value too great for base` and no non-zero exit.

### FR15a — state.json round-trip

Met, on both real and synthetic data. See AC13. Confirmed specifically that `verdict`, `url`,
`tasks`, and `branch` survive and that both `at` timestamps are byte-identical, i.e. `set-phase`
saw an unchanged record and did not restamp. `note` is not part of the phase record
(`set-phase` routes `--note` only to the `status.md` Notes column), so there is nothing there to
lose.

### FR15b — archived state.json untouched

Met. Fixture `changes/archive/oldone/state.json` containing `"change": "oldone"`, phase
`archived`, `verdict: PASS`: after `--apply` renamed it to `archive/001-oldone`, `diff` against
the pre-run copy is empty. The recorded `change` stays the bare `oldone`, as intended — no
`archive/...` path is written.

### FR9/AC7 — dry run side-effect free

Met, verified by tree comparison rather than by reading code. `find .specclaw -printf '%p %s %T@'`
over 193 entries is identical before and after, `git status --porcelain` is empty, and no
`state.json` was rewritten.

### Ordering

Met. In a fixture containing `005-mid`, `2026-some-slug`, `2026-07-22-legacy`, and `plain`, the
generated `STATUS.md` orders them `005-mid`, `2026-some-slug` (numbered group, numeric),
then `2026-07-22-legacy`, `plain` (unnumbered group, lexical). `2026-07-22-legacy` sorts with the
unnumbered group; `2026-some-slug` sorts as numbered.

## Additional checks beyond the ACs

| Requirement | Result |
|-------------|--------|
| FR12 mid-build refusal | Refuses with exit 4 and `widget (checked-out branch specclaw/widget)` when that branch is HEAD, and with `widget (live git worktree)` when a worktree exists elsewhere. Once both are gone the run proceeds. |
| FR14 `git mv` vs `mv` | Inside a git tree the renames land in the index as `R  old -> new` (verified via `git status --porcelain`). Outside a git tree (fixtures under `/tmp` with no repo) plain `mv` is used and the run succeeds. |
| Edge case 8 (interrupted `--apply`) | A mixed part-numbered fixture refuses with exit 3; `--force --apply` recovers to `001-a`, `002-b`, `003-c`; a repeat `--force` dry run reports all three `(unchanged)` with `0 rename(s)`, and a repeat `--force --apply` is a no-op. Idempotent. |
| Edge case 9 (metacharacters) | Folders named `we*ird [x] (y)` and ``a$b`c'd`` renamed correctly to `001-…` / `002-…`; no glob widening, no injection. |
| Edge case 10 (missing state.json) | Folders with no `state.json` renamed with no warning and no failure. |
| NFR6 performance | 800 folders (400 active + 400 archived): `next-change-number` in **0.066 s**. Backfill planning over the same 800 in 3.2 s. |
| NFR4 (no new config keys) | Confirmed — no `config.yaml` or template change in the diff. |
| Version bump (project rule) | `plugin.json` and `marketplace.json` both `0.6.3 → 0.6.4`, in sync. |

## Full local test sweep

| Suite | Result |
|-------|--------|
| `run-change-numbering-tests.sh` | 160 passed, 0 failed (rc=0) |
| `run-long-orchestration-tests.sh` | 272 passed, 0 failed (rc=0) |
| `run-memory-parallelism-tests.sh` | 16 passed, 0 failed (rc=0) |
| `run-parser-tests.sh` | 30 passed, **11 failed** (rc=1) — pre-existing, see below |
| `run-phase-state-tests.sh` | 193 passed, 0 failed (rc=0) |
| `run-shellcheck-gate-tests.sh` | 22 passed, 0 failed (rc=0) |
| `run-status-row-tests.sh` | 26 passed, 0 failed (rc=0) |
| `run-synth-agent-tests.sh` | 10 passed, 0 failed (rc=0) |
| `shellcheck-gate.sh` (with shellcheck 0.9.0) | rc=0, baseline unmodified |

`run-parser-tests.sh`: the `jq`-not-installed diagnosis is **confirmed**, not assumed.
`command -v jq` finds nothing on this host; all 11 failing assertions are the ones that pipe
through `jq` (lines 77, 80, 111, 114, 122 and the NFR2 cases). The same suite executed from a
`git worktree` of **`main`** fails identically — 30 passed, 11 failed. Unrelated to this change.

## Spec requirements implemented incorrectly or not at all

None found.

## Not verified, and why

1. **AC15 / AC16 end-to-end skill execution.** `/specclaw:propose` and `/specclaw:archive` are
   model-driven SKILL.md prose, not executables, so they cannot be run headlessly and
   deterministically. Both were verified at every mechanical level instead: the underlying tool
   returns the right number (`003`), the SKILL.md instructions are explicit and unambiguous, the
   archive move preserves the name and produces the right `STATUS.md`/`state.json`/next-number
   behaviour when performed manually, and no competing date-prefix instruction survives anywhere
   in the plugin. The residual risk is only that a model disobeys correct instructions.
2. **CI green on GitHub.** Only the local equivalents were run; the workflow registration was
   confirmed by reading `.github/workflows/ci.yml`.
3. **AC14's `gh pr view` leg.** `gh` is unauthenticated in this environment, so `reconcile`
   reports PR state as `unknown` rather than resolving it. This is `reconcile`'s documented
   fail-closed behaviour and is orthogonal to the rename; the drift comparison before vs after
   the rename was unaffected.
