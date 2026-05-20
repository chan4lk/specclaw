# Proposal: Adopt Karpathy CLAUDE.md guardrails for build (and adjacent phases)

**Created:** 2026-05-20
**Status:** 🟡 Draft

## Problem

Coding agents spawned by `/specclaw:build` tend to drift: they over-engineer
tasks, touch adjacent code that wasn't in scope, add speculative abstractions,
and skip stating assumptions up-front. The current build skill orchestrates
*what* runs (wave loop, parallelism, commits) but says little about *how* an
agent should behave inside a task. The result is diff bloat, scope deviations
auto-logged as `design_gap` learnings, and rework during `/specclaw:verify`.

Andrej Karpathy's public CLAUDE.md
(https://github.com/multica-ai/andrej-karpathy-skills) is a tight set of four
behavioral rules — Think Before Coding, Simplicity First, Surgical Changes,
Goal-Driven Execution — that directly target these failure modes.

## Proposed Solution

Adopt the four rules verbatim (with attribution) as **behavioral guardrails**
that get injected into coding-agent prompts, and reference them from the
human-facing skill docs where they fit.

Concrete changes:

1. **New reference file** `plugins/specclaw/references/agent-guardrails.md`
   containing the four rules, lightly adapted with specclaw-specific framing
   (e.g. tie "Surgical Changes" to the task's declared `files:` list, tie
   "Goal-Driven Execution" to the spec's acceptance criteria).
2. **Build context injection** — extend `specclaw-build-context` so the
   payload handed to every coding agent prepends the guardrails. This is the
   highest-leverage spot: every Step 3c agent spawn picks them up automatically.
3. **Build skill doc** — add a short "Agent guardrails" section to
   `skills/build/SKILL.md` pointing at the reference, so operators understand
   what the agents are being told.
4. **Plan skill** — reference rule #1 (Think Before Coding) and #2 (Simplicity
   First) in `skills/plan/SKILL.md` to discourage over-decomposed task lists
   and speculative design.
5. **Verify skill** — reference rule #4 (Goal-Driven Execution) since verify
   is literally "did we hit the success criteria?" — the framing already
   matches, just make it explicit.

Propose / archive / status / init are unaffected — the guardrails are about
*coding behavior*, not lifecycle orchestration.

## Scope

### In Scope
- Add `plugins/specclaw/references/agent-guardrails.md` (verbatim rules +
  attribution + brief specclaw framing).
- Modify `specclaw-build-context` to prepend the guardrails to agent payloads.
- Update `skills/build/SKILL.md`, `skills/plan/SKILL.md`, `skills/verify/SKILL.md`
  to reference the guardrails where they fit.
- Update CHANGELOG.md and bump version.

### Out of Scope
- Rewriting or paraphrasing Karpathy's rules — keep verbatim for attribution.
- Adding the guardrails to non-coding skills (propose, archive, init, status,
  auth-*, issue, pr).
- Building a configurable / opt-out mechanism — these are universal defaults.
- Translating to other agent harnesses (Codex, Gemini) — specclaw already
  passes its payload as plain prompt text, so it propagates for free.

## Impact

- **Files affected:** 5 (estimated) — 1 new reference, 1 script modification
  (`specclaw-build-context`), 3 SKILL.md edits, plus CHANGELOG + version bump.
- **Complexity:** small
- **Risk:** low — additive prompt text; worst case is verbose payloads. No
  behavioral change to the orchestration loop itself. Easy rollback (revert
  the context-builder change).

## Open Questions

1. **Attribution format** — credit as "Adapted from Andrej Karpathy's CLAUDE.md
   (multica-ai/andrej-karpathy-skills, MIT)" at the top of the reference, OK?
2. **Verbatim vs. adapted** — Karpathy's text says "tests" a lot (rule #4
   examples). specclaw's verify step is broader (spec acceptance criteria,
   not just tests). Keep verbatim and let the specclaw framing footer
   recontextualize, or lightly edit the examples? Recommend: **verbatim** +
   footer note.
3. **Token cost** — the guardrails are ~50 lines. Acceptable to prepend to
   every coding-agent payload, or gate behind a config flag (`build.guardrails:
   true` default-on)? Recommend: **always-on, no flag** — too small to matter.
4. **License** — confirm the upstream repo's license permits redistribution
   (MIT per the org's other repos, but worth a check before vendoring).

---

**To proceed:** Review this proposal and approve to begin planning.
