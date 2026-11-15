# Verify Report: 047-specclaw-mod

**Verdict:** PASS
**Head:** b37a4da
**Date:** 2026-11-03 (re-verified after the bundle amendment; first PASS was 56713ef on 2026-11-02)

## Acceptance Criteria

- AC-1: pass. `tests/state.spec.ts` AC1 covers full and lean task lists, `[X]`, verdict, PR (nested and top-level), and the `archive/` skip.
- AC-2: pass. AC2 table: `{nope`, `null`, `42`, `[]`, `"s"`, `''`, `{"phase":5}` and non-string verdict/PR all give phase `?` without throwing.
- AC-3: pass. AC3: the current change is the active one with the newest `state.json` mtime.
- AC-4: pass. `tests/view.spec.ts` AC4 covers pane rows, band text, both empty states and the unreadable state.
- AC-5: pass. AC5 covers status text with and without a build in progress, and the unreadable state.
- AC-6: pass. `gate.spec.ts` AC6 (resolved-path table) plus kit tests drive Writes through the real gate: `place.test.ts` (23 spellings), `linked.test.ts` (3 link layouts × 4 spellings) and `failopen.test.ts`.
- AC-7: pass. AC7: `warn` allows with a message, `off` allows silently. The FR8 rows show a gate error lets the edit run with a toast.
- AC-8: pass. `claude plugin validate plugins/specclaw`: ✔ Validation passed (one directory warning: no icon). The mod is now part of the specclaw plugin.
- AC-9: pass, as amended. The mod ships inside `specclaw`, so `marketplace.json` no longer lists `specclaw-mod`. All 15 manifest and marketplace versions are 0.8.6.
- AC-10: pass. `plugins/specclaw/tests/run-mod-tests.sh` is registered in `.github/workflows/ci.yml`, with bun 1.3.14 and `@anthropic-ai/claude-code@2.1.316` installed there. It passes locally.

## Amendment (2026-11-03): bundled into specclaw, gate default warn

- **Gate default:** with no setting, an unapproved Write runs and a toast names `/specclaw:propose` (`place.test.ts`). `gateMode()` ignores case and spaces. Any other value is read as `warn`, and a session-start toast names it (`gate.spec.ts` MODE_ROWS, `mode.test.ts` through `register`; mutation-checked).
- **Older clients:** Claude Code 2.1.250 rejected `userConfig.gate.options` and dropped the whole plugin. `options` was removed. Live check: 2.1.250 loads the bundle, its 9 skills and the SessionStart router, and skips only the mod. A 2.1.317 session loads it with the mod.
- **Plugin set:** `run-plugin-split-tests.sh` AC-7 ("five plugins share one version") failed on this branch before the bundle and passes now.
- **Pane open failure:** a rejected `ui.open` now gives a toast and a plain reply (`pane.test.ts`; mutation-checked).

## Commands

| Command | Exit |
|---|---|
| `bash plugins/specclaw/tests/run-mod-tests.sh` (16 bun + 62 kit tests, validate) | 0 |
| `bash plugins/specclaw/tests/run-plugin-split-tests.sh` | 0 |
| `bash plugins/specclaw/tests/run-bootstrap-hook-tests.sh` (44 pass) | 0 |
| `bash plugins/specclaw/tests/run-codex-plugin-tests.sh`, `run-codex-skill-tests.sh` | 0 |
| All 52 CI-registered suites, run locally on macOS | 37 pass, 15 fail. The same 15 fail on `origin/main` (e7b3be8) on this machine and pass in CI on Linux, so they are environmental (see open PR #100). |
| `specclaw-quality-scan . --gate` | 0 |
| `specclaw-preset-check .` | 1: pre-existing violations only, none in `plugins/specclaw/hooks` or `tests` |
| `specclaw-review verdict --change 047-specclaw-mod` | 0 |
| `tsc -p plugins/specclaw` | not run: the gitignored `.claude-plugin/types/` API files were lost in the move and could not be regenerated. `plugin validate` checks the state contract. |

TypeScript 5.8 and older hit TS2589 (instantiation too deep) once the engine's tool types are present; 5.9.3 is clean.

## Live checks

- `claude -p --plugin-dir` smoke test in a scratch project: a Write was denied while the only change was a draft, and allowed once approved.
- The mod is hot-loaded in the authoring session; the operator was asked to look at the pane, band and status line there.
- Screenshots: not taken. The mod draws in the terminal, so the Playwright comparison does not apply.

## Review

**Review:** CLEAN. 26 rounds, final pass b37a4da (sonnet rounds, opus final). Last round 0/0/4 b/M/m; the minors are in `follow-ups.md`.
**Code Review:** APPROVED_WITH_NOTES. Amendment: 0 BLOCK, 2 WARN, 2 NOTE. Both WARNs were resolved: the old-client question was tested live, and the uninstall note was dropped because `specclaw-mod` never shipped. Prior review (59d4bc3) was APPROVED_WITH_NOTES with 6 findings.

Operator decisions: gate errors fail open (review rule R2); the gate resolves paths through realPath; the gate is a guard rail, not a sandbox (review rule R3). Deferred items are in `follow-ups.md`.
