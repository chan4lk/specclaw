# Verify Report: 047-specclaw-mod

**Verdict:** PASS
**Head:** 56713ef
**Date:** 2026-11-02

## Acceptance Criteria

- AC-1: pass. `tests/state.spec.ts` AC1 covers full and lean task lists, `[X]`, verdict, PR (nested and top-level), and the `archive/` skip.
- AC-2: pass. AC2 table: `{nope`, `null`, `42`, `[]`, `"s"`, `''`, `{"phase":5}` and non-string verdict/PR all give phase `?` without throwing.
- AC-3: pass. AC3: the current change is the active one with the newest `state.json` mtime.
- AC-4: pass. `tests/view.spec.ts` AC4 covers pane rows, band text, both empty states and the unreadable state.
- AC-5: pass. AC5 covers status text with and without a build in progress, and the unreadable state.
- AC-6: pass. `gate.spec.ts` AC6 (resolved-path table) plus kit tests drive Writes through the real gate: `place.test.ts` (23 spellings), `linked.test.ts` (3 link layouts × 4 spellings) and `failopen.test.ts`.
- AC-7: pass. AC7: `warn` allows with a message, `off` allows silently. The FR8 rows show a gate error lets the edit run with a toast.
- AC-8: pass. `claude plugin validate plugins/specclaw-mod`: ✔ Validation passed.
- AC-9: pass. `marketplace.json` lists `specclaw-mod`, and all 17 manifest and marketplace versions are 0.8.5.
- AC-10: pass. `run-mod-tests.sh` is registered in `.github/workflows/ci.yml`, with bun 1.3.14 and `@anthropic-ai/claude-code@2.1.316` installed there. It passes locally.

## Commands

| Command | Exit |
|---|---|
| `bash plugins/specclaw-mod/tests/run-mod-tests.sh` (7 bun + 55 engine tests, validate) | 0 |
| `npx -p typescript@5.9.3 tsc -p plugins/specclaw-mod` | 0 |
| `specclaw-quality-scan . --gate` | 0 |
| `specclaw-preset-check .` | 1: 17 violations, all pre-existing, none in files this change touches |
| `bash plugins/specclaw/tests/run-codex-plugin-tests.sh` | 0 |
| CI version-sync script | 0 |
| `specclaw-review verdict --change 047-specclaw-mod` | 0 |

TypeScript 5.8 and older hit TS2589 (instantiation too deep) once the engine's tool types are present; 5.9.3 is clean.

## Live checks

- `claude -p --plugin-dir` smoke test in a scratch project: a Write was denied while the only change was a draft, and allowed once approved.
- The mod is hot-loaded in the authoring session; the operator was asked to look at the pane, band and status line there.
- Screenshots: not taken. The mod draws in the terminal, so the Playwright comparison does not apply.

## Review

**Review:** CLEAN. 18 rounds, final pass 56713ef (sonnet rounds, opus final); last round 0/0/0 b/M/m.
**Code Review:** APPROVED_WITH_NOTES, 6 findings: 0 BLOCK, 3 WARN, 3 NOTE. All three WARNs were addressed in later rounds (state.json self-approval, path normalisation; sticky approval is documented).

Operator decisions: gate errors fail open (review rule R2); the gate resolves paths through realPath; the gate is a guard rail, not a sandbox (review rule R3). Deferred items are in `follow-ups.md`.
