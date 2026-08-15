# Verification Report: prompt-hardening

**Verified:** 2026-07-16
**Model:** claude-fable-5
**Verdict:** PASS

## Acceptance Criteria

(Verdicts follow the quote-first discipline this change introduces — each cites the exact evidence line.)

- ✅ **AC1 — Quote-first verdicts.** Live verify payload appends: "Before writing any verdict, first extract the exact quotes your judgment rests on into a 'Quotes' section". code-reviewer.md: "Every finding must quote the exact line(s) of code it flags... drop it rather than report a vague suspicion." PASS.
- ✅ **AC2 — Investigate before answering.** Live build payload (T1 run): "Never speculate about code you have not opened. If a claim depends on a file's contents, read that file first." PASS.
- ✅ **AC3 — Anti-reward-hacking.** Live build payload: "Tests verify correctness; they do not define the solution. Do not hard-code values or special-case logic just to make specific test inputs pass." Same payload serves loop fix turns (`--failure-record` appends to this base). PASS.
- ✅ **AC4 — Task-last ordering.** Live payload section sequence (grep `^## `): Agent Guardrails (line 3) → Specification Context (96) → Design Context (158) → Existing Code (708) → Working Rules (740) → Your Task (751) → Constraints (758). Guardrails first, task last. PASS.
- ✅ **AC5 — Motivated constraints.** Live payload: "other files may belong to parallel tasks in this wave, and out-of-list edits are auto-logged as design_gap scope deviations"; "the verify gate consumes this evidence to judge the change's acceptance criteria." PASS.
- ✅ **AC6 — Few-shot examples.** agent-prompts.md contains `<example type="good finding">` / `<example type="bad finding — do NOT produce">` and `<example type="strong acceptance criterion">` / weak pair. PASS.
- ✅ **AC7 — Reversibility list.** loop/SKILL.md: "no deleting files or branches, no `git push --force`, no `git reset --hard`, no bypassing safety checks (e.g. `--no-verify`)... halt and report instead — that is an escalation, not a fix." PASS.
- ✅ **AC8 — Research discipline.** spec-author.md gains "## Research Discipline": "Competing hypotheses... Confidence tracking... Self-critique before finalizing." PASS.
- ✅ **AC9 — Guardrails verbatim.** `git diff` on `references/agent-guardrails.md` across the branch: empty — file untouched. PASS.
- ✅ **AC10 — Suite + syntax.** `run-parser-tests.sh`: "13 passed, 0 failed" (full base suite for this branch). `bash -n` clean on both touched scripts. PASS.
- ✅ **AC11 — Docs + version.** README "Evidence-Grounded Agent Payloads" section; CHANGELOG 0.5.2 entry; `"version": "0.5.2"` in both plugin.json and marketplace.json. PASS.

## Test Results

```
$ bash plugins/specclaw/tests/run-parser-tests.sh
13 passed, 0 failed  (exit 0)
```

## Issues Found

None. Note (not an issue): live-payload greps matched the script's own heredoc quoted inside the Existing Code section as well as the real payload tail — evidence above cites the payload-tail occurrences (lines 740+).

## Summary

**Passed:** 11/11 criteria
**Failed:** 0/11 criteria
**Verdict:** PASS
