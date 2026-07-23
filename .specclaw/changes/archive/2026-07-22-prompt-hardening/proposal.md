# Proposal: Prompt Hardening — Evidence-Grounded Agent Payloads

**Created:** 2026-07-16
**Status:** 🟡 Draft

## Problem

_What problem are we solving? Why does it matter?_

SpecClaw's agent payloads (build, verify, code-review, spec-author, loop fix agents) predate current prompt-engineering guidance from both Anthropic and OpenAI. Audit against the published best practices found concrete gaps that cost accuracy:

1. **Payload ordering fights the model.** Anthropic's long-context guidance: "Put longform data at the top... queries at the end can improve response quality by up to 30%." SpecClaw payloads lead with instructions and bury the task between content blocks.
2. **No quote-first grounding in verdicts.** Verify/review agents judge directly from a large payload. Anthropic: "ask Claude to quote relevant parts of the documents first before carrying out its task."
3. **No investigate-before-answering rule.** Nothing stops a coding/fix agent from speculating about files it never opened.
4. **Reward hacking is guarded mechanically but not verbally.** The loop reverts test edits after the fact; the payload never tells the fix agent "tests verify correctness, not define the solution."
5. **Bare imperatives without motivation.** Constraints like "ONLY modify the files listed" carry no *why*; Anthropic: explanation improves compliance ("Claude is smart enough to generalize from the explanation").
6. **Zero few-shot examples** in agent-prompts.md; both vendors rank examples among the most reliable steering tools.
7. **No reversibility/safety guidance** for semi-autonomous loop turns (force-push, --no-verify, destructive shortcuts).

## Proposed Solution

_What are we building? High-level approach._

Text-level hardening of agent payloads and prompt templates. No behavioral logic changes; every item is additive prompt text, project-agnostic, and sourced from published vendor guidance.

1. **Payload reorder (build + verify payloads):** brief identity → longform context (spec, design, code, docs) → task + constraints + output contract at the end. Static guardrails stay first (prompt-cache friendly).
2. **Quote-first verdicts:** verify and code-review prompts instruct: first extract the exact quotes (AC lines, code lines, test output) the verdict/finding rests on into a quotes section, then judge. Findings without quotable evidence are not findings.
3. **Investigate-before-answering block** (build/fix/review payloads): "Never speculate about code you have not opened... read the file before making claims about it."
4. **Anti-reward-hacking block** (build + loop fix payloads): general-purpose solutions; no hard-coding to test inputs; report incorrect tests instead of working around them.
5. **Motivated constraints:** existing payload constraints gain one-line whys (scope limits ↔ parallel-task conflicts + design_gap auto-logging; test evidence ↔ verify gates).
6. **Few-shot examples in agent-prompts.md:** one good/bad finding pair for code-reviewer, one well-formed AC for spec authoring, wrapped in example tags.
7. **Reversibility guidance** (loop fix agent): confirm-or-avoid list for destructive/hard-to-reverse/externally-visible actions; never bypass safety checks.
8. **Structured-research directive** (spec-author + verify): competing hypotheses, confidence tracking, self-critique.
9. **Housekeeping lines:** temp-file cleanup after task; subagent-vs-direct calibration note in build skill.

Guardrails reference keeps its verbatim-Karpathy section untouched; additions land in the payload builders and the specclaw-specific footer only.

## Scope

### In Scope
- `references/agent-prompts.md` — template reorder, quote-first steps, examples.
- `bin/specclaw-build-context` — section order, investigate/anti-reward-hack/motivation blocks.
- `bin/specclaw-verify-context` — quote-first instruction, ordering.
- `agents/code-reviewer.md`, `agents/spec-author.md` — quote-evidence + research directives.
- `skills/loop/SKILL.md` (fix-agent payload notes) + `skills/build/SKILL.md` (calibration/cleanup lines).
- Byte-identity is NOT preserved (text changes are the feature); regression = existing test suite stays green.
- README note + CHANGELOG + version bump.

### Out of Scope
- Any control-flow/logic change in scripts.
- Guardrails verbatim section (stays Karpathy-verbatim by design).
- Model routing changes; per-model prompt variants.
- smart-base-branch (separate change).

## Impact

- **Files affected:** ~9 (estimated)
- **Complexity:** medium (text-heavy, logic-light)
- **Risk:** low — prompt text only; suite must stay green; payload structure changes reviewed against both vendor docs

## Open Questions

1. Payload reorder may conflict textually with PR #32 (grounded-context touches the same builders). **Recommendation:** land after #32 merges; trivial rebase otherwise.
2. Add examples inline in agent-prompts.md or as separate reference file? **Recommendation:** inline in the template they steer — keeps prompt-cache locality and discoverability.

---

**To proceed:** Review this proposal and approve to begin planning.
