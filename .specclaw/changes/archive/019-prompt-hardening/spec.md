# Spec: Prompt Hardening — Evidence-Grounded Agent Payloads

**Change:** prompt-hardening
**Created:** 2026-07-16
**Status:** 🟡 Draft

## Overview

Harden SpecClaw's agent payloads and prompt templates against the accuracy failure modes named in Anthropic's and OpenAI's published prompt-engineering guidance: ungrounded verdicts, speculation about unopened code, reward hacking, unmotivated constraints, missing examples, and payload ordering that buries the task. Text-only change: no control flow is modified; the existing test suite must stay green.

## Requirements

### Functional Requirements

- **FR1 — Quote-first verdicts.** The verify-agent template and code-reviewer agent instruct: before judging, extract the exact quotes (spec AC lines, code lines, test-output lines) the verdict or finding rests on; a finding without quotable evidence must not be reported. (Anthropic: "ask Claude to quote relevant parts of the documents first before carrying out its task.")
- **FR2 — Investigate before answering.** Build-agent and loop-fix payloads carry: never speculate about code not opened; read files before making claims about them. (Anthropic hallucination-minimization block.)
- **FR3 — Anti-reward-hacking text.** Build/fix payloads state: general-purpose solutions; no hard-coding to test inputs; tests verify correctness, not define the solution; report incorrect/infeasible tests instead of working around them.
- **FR4 — Task-last payload ordering.** Build payload ends with the task, files list, constraints, and output contract (longform spec/design/code content above them); static guardrails remain first for prompt-cache locality. (Anthropic: queries at the end improve quality up to 30%.)
- **FR5 — Motivated constraints.** Payload constraint lines carry a one-line why (scope limit ↔ parallel-task conflicts + design_gap auto-logging; test evidence ↔ verify gate).
- **FR6 — Few-shot examples.** agent-prompts.md gains a good/bad finding example pair for the code reviewer and a well-formed vs vague AC example for spec authoring, wrapped in `<example>` tags.
- **FR7 — Reversibility guidance.** Loop skill fix-agent instructions gain a confirm-or-avoid list: destructive ops, hard-to-reverse ops, externally visible ops; never bypass safety checks (e.g. `--no-verify`) to get a gate green.
- **FR8 — Structured research directive.** spec-author agent gains: competing hypotheses, confidence tracking, self-critique while authoring.
- **FR9 — Housekeeping.** Build payload: clean up temporary helper files at task end. Build skill: subagent-vs-direct calibration note.
- **FR10 — Docs + version.** README note, CHANGELOG entry, version bump in both version files.

### Non-Functional Requirements

- **NFR1 — Text-only.** No script control-flow changes; `bash -n` clean; test suite unchanged and green.
- **NFR2 — Verbatim guardrails preserved.** The Karpathy section of agent-guardrails.md is byte-identical before/after.
- **NFR3 — Project-agnostic.** No stack-specific advice in any added text.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- [ ] **AC1** — Verify payload output contains the quote-first instruction; code-reviewer.md requires quoted evidence per finding.
- [ ] **AC2** — Build payload output contains the investigate-before-answering block.
- [ ] **AC3** — Build payload output contains the anti-reward-hacking block (visible in loop fix turns too, which reuse specclaw-build-context).
- [ ] **AC4** — In the build payload, the task title/files/constraints/output contract appear after spec/design/code content; guardrails remain the first section.
- [ ] **AC5** — Constraint lines in the build payload include motivations (grep-checkable "why" phrasing for scope and test lines).
- [ ] **AC6** — agent-prompts.md contains `<example>`-tagged good/bad reviewer finding and strong/weak AC pairs.
- [ ] **AC7** — Loop SKILL.md contains the reversibility/no-safety-bypass list.
- [ ] **AC8** — spec-author.md contains the structured-research directive.
- [ ] **AC9** — `git diff` on references/agent-guardrails.md shows no change inside the verbatim Karpathy section.
- [ ] **AC10** — `bash plugins/specclaw/tests/run-parser-tests.sh` passes; `bash -n` clean on touched scripts.
- [ ] **AC11** — README/CHANGELOG updated; version bumped to 0.5.2 in both version files.

## Edge Cases

- Loop fix turns reuse `specclaw-build-context` — FR2/FR3 text must read correctly in both fresh-build and remediation contexts.
- Payload reorder must not break `--failure-record`/`--reflection` appends (they attach after the base payload).
- Existing changes' payloads regenerate with new text — no stored-payload compatibility concerns (payloads are ephemeral).

## Dependencies

- Textually adjacent to PR #32 (grounded-context) in the same builders; whichever merges second takes a trivial rebase.

## Notes

Sources: Anthropic "Prompting best practices" (long-context ordering, quote grounding, hallucination minimization, overeagerness, reward-hacking, reversibility, research structure, subagent calibration, file cleanup) and OpenAI prompt-engineering guide (message hierarchy, section ordering, few-shot, caching locality).
