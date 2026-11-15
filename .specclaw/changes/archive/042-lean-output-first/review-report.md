# Code Review Report: 042-lean-output-first

**Reviewed:** 2026-10-12
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

13 findings: 0 BLOCK, 6 WARN, 7 NOTE

Scope: new and substantively changed code only. Pure `git mv` renames and the moved body of `lib/quality-scan.sh` were not re-reviewed. Test runs on this machine: lean-flow, plugin-split, preset-check, quality-scan, description-lint, bootstrap-hook and codex-plugin suites pass, and the shellcheck gate reports no new findings. `plugins/specclaw-bf/tests/run-quality-tests.sh` (AC-13) fails 9 cases (15a, 23h, 25c-h, 28e). The same 9 fail on `main` here, because jscpd and lizard are not installed locally, so this is not a regression. It means AC-13 is unverified in this environment.

## Findings

### [WARN] plugins/specclaw/skills/build/SKILL.md:step 3 — Correctness (destructive command)
**Problem:** The refactor rollback says "otherwise discard it with `git restore .`". That reverts every uncommitted tracked change in the tree, not only the refactor. `specclaw-build commit` stages only the files it is given (`bin/specclaw-build:351`: `git add -- "${files[@]}"`). So the `change.md` checkbox edits made by `specclaw-update-task-status` before each commit are still uncommitted, and the rollback reverts them. Completed tasks would read as pending again. It would also destroy any unrelated uncommitted work the user has. design.md decision 11 has the same flaw (`git checkout -- .`).
**Fix:** Name the paths. Record the files the refactor touched, then run `git restore -- <those files>` and delete only the files it created. Alternatively commit `change.md` after each task, or commit the refactor first and `git revert` it.

### [WARN] plugins/specclaw/hooks/session-start:80-87 — Correctness (cross-plugin resolution)
**Problem:** The missing-plugin notice is decided by `command -v specclaw-gh-sync` (and `specclaw-bf-status`, `specclaw-party`) in the hook's own environment. The design relies on PATH containing every installed plugin's `bin/`. Nothing shows that hook subprocesses get the same PATH as the Bash tool. If they do not, every user who has `specclaw-sync` installed still gets "not installed: /plugin install specclaw-sync@chan4lk" on every session. AC-8 is tested only with `PATH="/usr/bin:/bin"`, so the installed-and-detected case (no notice) is never tested.
**Fix:** Also accept a sibling plugin directory, e.g. `[ -d "$PLUGIN_DIR/../../$3" ] || [ -d "$PLUGIN_DIR/../$3" ]`, in addition to `command -v`. Add a test where a fake `specclaw-gh-sync` is on PATH and no notice appears.

### [WARN] plugins/specclaw/bin/specclaw-pr:~398 — Correctness (lean verdict)
**Problem:** In lean mode `verify_file` is `change.md`. The line `verdict="$(grep -oiE '\b(PASS|FAIL|PARTIAL)\b' "$verify_file" | head -1)"` then scans the whole file. The first "pass", "fail" or "partial" anywhere wins, including the Problem text ("tests fail today") or an AC such as "login passes". The PR body can show the wrong verdict. The same applies to the keyword greps in `enforce_test_policy`, which match the whole of `change.md` and so can be satisfied by AC text rather than verify evidence.
**Fix:** In lean mode, read the `^\*\*Verdict:\*\*` line (e.g. `grep -m1 -oE '^\*\*Verdict:\*\* *[A-Z]+'`), and run the evidence greps over `extract_section "$f" Verify`.

### [WARN] plugins/specclaw/bin/specclaw-validate-change:~72-79 — Correctness
**Problem:** `verified()` is `grep -qE '^\*\*Verdict:\*\*' change.md`. A lean verify that writes `**Verdict:** FAIL` therefore satisfies the `pr` and `archive` gates. `skills/pr/SKILL.md` step 1 only says to stop "if `## Verify` has no `**Verdict:**`". With the full flow, `verify-report.md` has the same weakness. For lean, though, the template and skill explicitly define a PASS/FAIL value.
**Fix:** Require `^\*\*Verdict:\*\*[[:space:]]*PASS` for the `pr` phase.

### [WARN] plugins/specclaw/skills/init/SKILL.md; plugins/specclaw/tests/run-lean-flow-tests.sh:46-48 — Spec coverage (AC-5 / FR-10)
**Problem:** FR-10 and AC-5 cover "each of the 8 core lifecycle SKILL.md files", each with a dispatch line and an existing `references/full/<phase>.md`. `init/SKILL.md` has no dispatch line, and `references/full/` has no `init.md`. The test treats init separately: it checks only the word count (`words="$(awk … init/SKILL.md …)"`), so the gap passes silently. The behaviour is defensible, since init runs before any `flow` key exists. But either the spec or the implementation should change.
**Fix:** Amend FR-10/AC-5 to say 7 phases plus init, or add the dispatch line and `references/full/init.md`.

### [WARN] plugins/specclaw/tests — Test quality (AC coverage gaps)
**Problem:**
- AC-4 says the screenshot "writes a PNG when Playwright is present and exits 3 otherwise". Only the exit-3 branch is tested (`PATH="/usr/bin:/bin" … specclaw-screenshot`). The success branch and the `[ -s "$out" ]` check are untested.
- AC-8's second clause, "a lean propose does not fail", is tested only through `specclaw-validate-change … build`, which is not propose.
- AC-7 asserts versions equal across `.claude-plugin/marketplace.json` and the 8 manifests. FR-11 says "both marketplace files" list all four plugins. `run-plugin-split-tests.sh` never opens `.agents/plugins/marketplace.json`. `run-codex-plugin-tests.sh` does check the names and paths.
- FR-16 notices for `bf` and `extras` have no test. FR-21 and FR-24 (verify runs preset-check and the quality gate) exist only as skill prose.
- `run-quality-scan-tests.sh` "tools absent" case runs with `PATH="$TMP/bare:/usr/bin:/bin"`. On a host where `/usr/bin` holds `npx` or `uvx`, the scan would run the real tools and the `not_run` assertion would fail.
**Fix:** Add a fake-`npx` PNG case. Add a `.agents` marketplace assertion. Make the bare PATH contain only the symlinks.

### [NOTE] plugins/specclaw/bin/specclaw-validate-change:61-71 — Design adherence (D8)
**Problem:** design.md decision 3 and the risks table say `validate-change` "refuses a lean artifact set on a `full` project and the reverse". The code rejects only a mixed folder (`change.md` plus `proposal.md`/`spec.md`/`design.md`/`tasks.md`). It never consults `specclaw-flow`, so a lean `change.md` on a `flow: full` project validates. The mixed-set refusal also has no test.
**Suggestion:** Either add the flow check, or drop the claim from design.md.

### [NOTE] plugins/specclaw/bin/specclaw-screenshot:19 — Correctness
**Problem:** `grep -qiE "could not determine executable|not found|executable doesn't exist|npm error|install"` classifies any Playwright output containing "install" or "not found" as exit 3 (unavailable). A genuine capture failure whose message contains those words is reported as unavailable instead of failing. The result is safe, since exit 3 means a human compares, so a failure is never recorded as a pass. It is imprecise against the stated contract "any other code: a real failure".
**Suggestion:** Match `Executable doesn't exist|could not determine executable|npx canceled` only.

### [NOTE] plugins/specclaw/bin/specclaw-init:~52 — Security / robustness
**Problem:** `sed "s|{{project_name}}|$PROJECT_NAME|g"` breaks on a name containing `|` or `&`. It also injects an unescaped name into the HTML mock. This is the same pattern as the existing config `sed`.
**Suggestion:** Escape the name, or substitute with awk or parameter expansion.

### [NOTE] plugins/specclaw/bin/specclaw-preset-check — Correctness (accepted limitation)
**Problem:** Comment detection is whole-line only (as design.md accepts). So a `#` or `//` line inside a Python triple-quoted string or a JS template literal, `///` XML docs in C#, and a code line sharing `*/` with a closing block comment are all handled imprecisely. `int(override(cfg, "max_lines", 80))` also raises an uncaught `ValueError` traceback on a malformed override.
**Suggestion:** Wrap the `int()` in a try block and exit 2 with a message.

### [NOTE] plugins/specclaw/skills/build/SKILL.md; plugins/specclaw/bin/specclaw-build — Design adherence
**Problem:** Lean build never records the build phase as done. It does not call `specclaw-build finalize` (which reads `tasks.md` at line 500) or `specclaw-set-phase … build done`, so the state.json build phase and the STATUS row may lag. Verify validates by counting the tasks in `change.md`, so the flow still works.
**Suggestion:** Add `specclaw-set-phase .specclaw <change> build done` after the last task.

### [NOTE] plugins/specclaw/hooks/session-start; plugins/specclaw/templates/config.yaml:216 — Design
**Problem:** The template defaults `party.enabled: true`. FR-16 prints the "install specclaw-extras" line when that is true. So every pre-existing full-flow project without extras sees the notice at every session start, including projects that never used the panel. This is spec-conformant but noisy.
**Suggestion:** Consider showing it once, or only when the party has been used.

### [NOTE] plugins/specclaw/tests/shellcheck-baseline.txt; plugins/specclaw/tests/shellcheck-gate.sh:49 — NFR-3
**Problem:** NFR-3 says the baseline is "unchanged". The diff also drops the `specclaw-loop SC2015` entry (the comment-only edits to `specclaw-loop` fixed the underlying finding), in addition to the path renames for the moved scripts. The gate output is fine (23 known, none new), and removal is the safe direction. `mapfile` in the gate is bash 4 only. That is pre-existing and runs in Linux CI, but it fails on macOS system bash 3.2.
**Suggestion:** Note the removal in the change record.

## Cross-plugin resolution check

- The `_core_bin="$(dirname "${BASH_SOURCE[0]}")/../../specclaw/bin"; [ -d … ] && PATH=…` lines in `specclaw-azdo-pr`, `specclaw-bf-analyze-codebase` and `specclaw-bf-quality-collect` resolve only in a repo checkout. In the plugin cache the directory does not exist, so the test fails harmlessly and the scripts rely on PATH, as designed. A bare `[ -d ] && …` at top level does not trip `set -e`.
- `specclaw-bf-quality-collect` derives `CORE_LIB` from `command -v specclaw-flow`, with a clear `die` if `lib/quality-scan.sh` is missing. That works in the cache and on core version skew. `specclaw-quality-scan` itself uses `../lib` and stays inside core.
- `specclaw-azdo-pr` calls `specclaw-change-lock` and `specclaw-validate-change` by bare name at lines 62-64 and 135. If core is not on PATH, `acquire` exits 127 under `set -e`. That is acceptable, since sync requires core, but it gives no message naming the missing plugin.
- The skills' `specclaw-gh-sync` calls are guarded "if on PATH … skip silently". `validate-change` guards with `command -v`. Both are consistent with FR-13.
- `.git` jscpd ignore (`--ignore "**/.git/**${globs:+,$globs}"`) and `excl_dir_names` always emitting `.git` are correct.

## Verdict Rationale

No finding is a blocking defect. The lean flow, the preset checker and the quality scan work as specified on the paths tested. Cross-plugin resolution matches the PATH-based design, and the shellcheck gate shows no new findings. The six warnings need attention before merge:
- the `git restore .` rollback in the lean build text can discard task-status edits and unrelated uncommitted work;
- the lean PR verdict and gate logic is imprecise (a FAIL verdict passes the gate, and the verdict grep scans the whole file);
- the missing-plugin notice depends on the hook's PATH, and the installed case is untested;
- the init skill does not match the AC-5 wording;
- several acceptance criteria are only partly covered by tests.
