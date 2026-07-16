# Design: Prompt Hardening — Evidence-Grounded Agent Payloads

**Change:** prompt-hardening
**Created:** 2026-07-16

## Technical Approach

Pure prompt-text surgery in the two payload builders, the agent prompt reference, the two agent definitions, and two skills. Each hardening block is a named, delimited paragraph so future diffs stay reviewable. No parsing, flow, or interface changes anywhere.

Build payload (specclaw-build-context) target order (FR4):
1. Identity line (cache-stable)
2. Agent Guardrails (static, cache-stable)
3. Repo Knowledge Base / Project Context (curated)
4. Specification + Design + Existing Code (longform)
5. Hardening blocks: investigate-before-answering, anti-reward-hacking, housekeeping
6. Task: title, notes, files list, motivated constraints, output contract (LAST)

Verify payload (specclaw-verify-context): quote-first instruction appended to the template's task framing — the agent must emit a quotes section before its verdict.

## Architecture

No new components. Touched text surfaces:

```
bin/specclaw-build-context      — section reorder + FR2/FR3/FR5/FR9 blocks
bin/specclaw-verify-context     — FR1 quote-first instruction
references/agent-prompts.md     — template ordering mirror + FR6 examples
agents/code-reviewer.md         — FR1 quoted-evidence requirement per finding
agents/spec-author.md           — FR8 research directive
skills/loop/SKILL.md            — FR7 reversibility list
skills/build/SKILL.md           — FR9 subagent calibration note
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-build-context` | modify | Reorder prompt assembly; add investigate/anti-reward-hack/housekeeping blocks; motivate constraints |
| `plugins/specclaw/bin/specclaw-verify-context` | modify | Quote-first verdict instruction |
| `plugins/specclaw/references/agent-prompts.md` | modify | Mirror ordering; `<example>` pairs (reviewer finding, AC quality) |
| `plugins/specclaw/agents/code-reviewer.md` | modify | Quoted-evidence requirement; drop unquotable findings |
| `plugins/specclaw/agents/spec-author.md` | modify | Structured-research directive |
| `plugins/specclaw/skills/loop/SKILL.md` | modify | Reversibility / no-safety-bypass guidance for fix agents |
| `plugins/specclaw/skills/build/SKILL.md` | modify | Subagent-vs-direct calibration line |
| `README.md`, `CHANGELOG.md`, version files | modify | FR10 |

## Data Model Changes

None.

## API Changes

None. Script CLIs unchanged; payload content changes only.

## Key Decisions

1. **Blocks over rewrites** — each guideline lands as a delimited, named block; reviewers can trace every line to a vendor source.
2. **Guardrails stay verbatim** — hardening text lives in builders/agents, not inside the Karpathy section (NFR2); keeps the vendored reference honestly vendored.
3. **Task-last, guardrails-first** — merges Anthropic's data-top/query-bottom rule with cache locality (static prefix unchanged across tasks).
4. **Examples inline in agent-prompts.md** — steering text belongs beside the template it steers (proposal Q2 resolution).
5. **Version 0.5.2** — distinct from the two open 0.5.1 PRs to avoid identical-version collisions; merge order still decides final numbering via rebase bumps.

## Grounding sources

- Anthropic prompting best practices — "Put longform data at the top... queries at the end can improve response quality by up to 30%"; "ask Claude to quote relevant parts of the documents first"; "Never speculate about code you have not opened"; "Tests are there to verify correctness, not to define the solution"; "don't bypass safety checks (e.g. --no-verify)".
- OpenAI prompt-engineering guide — section ordering (Identity → Instructions → Examples → Context), few-shot diversity, cache-friendly stable prefixes.
- `plugins/specclaw/CLAUDE.md` — loop fix-agent flow the FR7 text attaches to: "a fix agent (models.coding) makes the smallest diff to turn the failing gate green".

## Risks & Mitigations

- **Textual conflict with PR #32** (same builders) → additive blocks placed away from #32's discovered-docs section; trivial rebase either direction (spec Dependencies).
- **Payload reorder regressions** → AC4 asserts section order in live output; suite green required.
- **Prompt bloat** → blocks are short (3–6 lines each); total payload growth < 40 lines.
