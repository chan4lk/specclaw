# Verify Report: 042-lean-output-first

**Verdict:** PASS — 14 of 14 acceptance criteria verified. AC-14 was settled by CI on PR #93 (run 38256257545, all four checks green at `484f5ca`).

**Date:** 2026-10-12 · **Branch:** `specclaw/042-lean-output-first` · **HEAD:** 484f5ca (first verified at fd94b5b; AC-14 at 484f5ca)

## Acceptance criteria

| AC | Result | Evidence |
|---|---|---|
| AC-1 flow default/lean | ✅ | `run-lean-flow-tests.sh` AC-1 (2 checks) |
| AC-2 init lean defaults + offline mock | ✅ | `run-lean-flow-tests.sh` AC-2 (2 checks) |
| AC-3 change.md-only change validates and parses | ✅ | `run-lean-flow-tests.sh` AC-3 |
| AC-4 screenshot PNG / exit 3 | ✅ | Exit 3: `run-lean-flow-tests.sh` AC-4. PNG branch checked by hand: `specclaw-screenshot` on a fresh init's mock wrote a 1280×800 PNG, opened and inspected (Playwright via npx). Not in CI; it needs a browser. |
| AC-5 lean skills ≤300 words, full references | ✅ | `run-lean-flow-tests.sh` AC-5 now covers all 8, init included (fixed during verify: `references/full/init.md` added) |
| AC-6 no bf/brownfield/rebuild in core skills and references | ✅ | `run-plugin-split-tests.sh` AC-6 |
| AC-7 four plugins, one version | ✅ | `run-plugin-split-tests.sh` AC-7; `run-codex-plugin-tests.sh` |
| AC-8 notice + lean flow without sync | ✅ | `run-plugin-split-tests.sh` AC-8, which now also checks that an installed add-on in the plugin cache is not reported missing |
| AC-9 description lint baseline same or smaller | ✅ | 60 → 0 entries across 37 skills; `run-description-lint-tests.sh`, `run-lint-meta-tests.sh` |
| AC-10 6 presets ≤60 lines, init proposes nextjs | ✅ | `run-preset-check-tests.sh` AC-10 |
| AC-11 preset-check fixtures | ✅ | `run-preset-check-tests.sh` AC-11 (4 checks) |
| AC-12 planted duplicate, gate exit 1 | ✅ | `run-quality-scan-tests.sh` (fake tools). Checked by hand with real jscpd 5.4.1 + lizard: planted 23-line duplicate found, gate fails |
| AC-13 brownfield quality suite on the shared scan | ✅ (no regression) | `run-quality-tests.sh`: 327 pass, 9 fail. The same 9 fail on `main` here (macOS; clone cases need tools this machine lacks). The 23i byte comparison against `main`'s collector passes. |
| AC-14 all suites pass in CI | ✅ | PR #93 CI run [38256257545](https://github.com/chan4lk/specclaw/actions/runs/38256257545) at `484f5ca`: Parser regression suite, ShellCheck bin scripts, Validate plugin manifests, Routing matrix all pass. The first CI run failed on two things, fixed below. |

## Gates

- **shellcheck gate:** no new findings (23 known). The baseline lost one stale `specclaw-loop` entry; it only shrank.
- **Test/lint/build commands:** none configured in `config.yaml`; the suites above are the evidence.
- **E2E:** not configured (`build.e2e_command` unset). No e2e evidence exists, and no AC depends on it.

## Regressions found and fixed during verify

- `run-staged-files-tests.sh` T12 failed because T12's description rewrite dropped "Use when" from the staged-files auditor. Restored.

## Fixes after the PR opened (to reach green CI)

- `66ae927` `specclaw-update-status`: the EXIT trap's `rm` set exit 127 on a PATH without `rm`, and the no-remote skip read "git not found" as "no remote" (and checked the cwd, not the project), so the `az` fallback never ran. Both fixed; the NFR2 test shim gains `dirname` and `perl`.
- `484f5ca` ShellCheck: CI's older apt shellcheck reports SC2317 where 0.11 reports SC2329 (`specclaw-quality-scan`, now disables both), and still flags the SC2015 in `specclaw-loop` that verify had dropped from the baseline (rewritten as an `if`).
- `2b0d64f` Brownfield collector cases 9–12 and the `analyze/` and `rebuild-plan/` fixtures moved from core's `run-parser-tests.sh` to `plugins/specclaw-bf/tests/run-bf-collect-tests.sh` (registered in CI). Pass count unchanged: 61 + 50 = 111.
- `3e543ce` `specclaw-init` and this repo's `.gitignore` ignore `.specclaw/changes/**/.lock/`.

## Code review fixes applied (fd94b5b)

- Lean `pr` and `archive` gates now require `**Verdict:** PASS`. Before, a FAIL verdict passed them.
- `specclaw-pr` reads the lean verdict from the `**Verdict:**` line only, not the first PASS/FAIL anywhere in `change.md`.
- The session-start notice also counts an add-on as installed when it sits beside core in the plugin cache, so hook environments without plugin `bin/` on PATH no longer report false "not installed".
- Refactor rollback restores only the refactor's own files. It was `git restore .`, which would also revert uncommitted task-status edits.
- `specclaw-init` escapes the project name and description for YAML and sed, and HTML-escapes the name in the mock. A name with `|` or `&` previously broke config generation (already true on `main`).
- `specclaw-preset-check` exits 2 with a message on a non-numeric `max_lines`, where it used to print a traceback.
- The quality-scan "tools absent" test no longer depends on the runner's `/usr/bin` having no `npx` or `uvx`.

## Open notes (accepted, not fixed)

- `preset-check` detects whole-line comments only, not trailing ones.
- `specclaw-screenshot` treats any output containing "install" or "not found" as Playwright unavailable (exit 3). That fails safe: the person compares by eye.
- `validate-change` does not cross-check a lean `change.md` against the project's `flow` value.
- Lean build does not record a `build` phase in `state.json`. Verify gates on task completion, which is unchanged.
- Existing full-flow projects keep the template default `party.enabled: true`, so without `specclaw-extras` they see the install notice each session. That is intended: their full flow uses the panel.
- `T14`'s build/verify wiring landed in the T16 commit, and the collector's `CORE_LIB` lines in T15, because they touch the same files.

**Code Review:** APPROVED_WITH_NOTES — 13 findings: 0 BLOCK, 6 WARN (5 fixed above; the test-gap warning only partly: AC-4 PNG checked by hand, the CI-portability case fixed, while the `.agents` marketplace and the bf/extras notices still have no dedicated test), 7 NOTE
