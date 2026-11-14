# Verify Report: 062-dash-pane

**Verdict:** PASS WITH FOLLOW-UPS (operator exit rule, 2026-11-14)
**Head:** cf74392 (code); the review records are committed on top of it

## Acceptance criteria

- AC-1: pass. `claude plugin validate plugins/specclaw-dash` passes (with the hooks-module warning). The marketplace lists `specclaw-dash` at 0.9.8, and the README table has its row.
- AC-2: pass. `scan.spec.ts`: exact tokens, cost, context, session names and role totals. A repeated message id is counted once. No prompt, tool or thinking text is in the scan result.
- AC-3: pass. `scan.spec.ts`: offset resume, a shorter file parsed from 0, a half line held back, a bad record counted.
- AC-4: pass. `loops.spec.ts` and `view.spec.ts`: phase, tasks, open span, rounds, escalations, final pass at or behind HEAD, lessons.
- AC-5: pass. Install cards and error lines in `view.spec.ts` and `pane.test.tsx`. Totals show `≥` when a transcript is skipped or a record is unreadable. A table test covers none / skipped / unreadable / both across the pane, band and status line (fix for `bdc8e6f60ea9`).
- AC-6: pass. `pane.test.tsx` opens `/dash`. The band and status line match the FR-2.5 text, and every cost sits under the "API-equivalent estimate" label.
- AC-7: pass. `run-mod-tests.sh`: the mod calls only `$.fs` exists/read/list/stat and no `$.process`.
- AC-8: pass. `run-suggest-tests.sh`: the dash tip prints when the plugin is absent and not when it is installed. Both status skills name the call.

## Commands

- `bash plugins/specclaw-dash/tests/run-mod-tests.sh`: exit 0. 35 spec tests, 13 mod tests, AC-7, plugin validate.
- `bash plugins/specclaw/tests/run-suggest-tests.sh`: exit 0, all pass.
- All 61 `plugins/*/tests/run-*.sh` at HEAD, side by side with all 60 at origin/main (1c03b41): 47 and 46 exit 0. The extra pass is the new `run-mod-tests.sh`. The same 14 fail on both, so they were already failing:
  - specclaw: change-numbering, long-orchestration, phase-state, synth-agent
  - specclaw-bf: bf-status, blueprint, prototype byte-identity, prototype gates, prototype readiness-scope, prototype stack-resolver, prototype status-machine, quality, replay-classification
  - specclaw-extras: party

## Review

- Rounds 1 to 7: see `review/round-*.json`. Round 7 (final pass 2) left one major, `bdc8e6f60ea9`, fixed in cf74392.
- Round 8 (delta since 4ab42ff, sonnet): clean, 0/0/1.
- Round 9 (operator-approved third final pass, opus): open, 0/1/4. `bdc8e6f60ea9` did not come back. The new major `4a32090c2fd6` (`loops.ts:15`, unparsed timeline lines dropped silently) and the minors are logged in `follow-ups.md` under the operator exit rule.
