# Spec: Adopt Karpathy CLAUDE.md guardrails for build (and adjacent phases)

**Change:** karpathy-build-guardrails
**Created:** 2026-05-20
**Status:** 🟡 Draft

## Overview

Inject Andrej Karpathy's four behavioral rules — Think Before Coding,
Simplicity First, Surgical Changes, Goal-Driven Execution — into every coding
agent spawned by `/specclaw:build`, and surface the same rules in the
human-facing skill docs for `build`, `plan`, and `verify`. Goal: reduce diff
bloat, scope deviations, and speculative abstractions in agent-produced code.

## Requirements

### Functional Requirements

- **FR1.** A new reference file `plugins/specclaw/references/agent-guardrails.md`
  exists and contains Karpathy's four rules **verbatim**, with attribution to
  `multica-ai/andrej-karpathy-skills` at the top and a short specclaw-specific
  framing footer that ties:
  - Rule 3 ("Surgical Changes") to the task's declared `files:` list.
  - Rule 4 ("Goal-Driven Execution") to spec acceptance criteria (not only
    tests).
- **FR2.** `specclaw-build-context` prepends the full contents of
  `agent-guardrails.md` as a top-level section (above "Your Task") to the
  prompt emitted to stdout, on every invocation.
- **FR3.** The guardrails section is always-on — no config flag, no opt-out.
- **FR4.** `skills/build/SKILL.md` gains an "Agent guardrails" subsection
  under "Key Principles" pointing at `references/agent-guardrails.md` and
  noting that the guardrails are auto-injected into every coding agent.
- **FR5.** `skills/plan/SKILL.md` references rules 1 (Think Before Coding) and
  2 (Simplicity First) where they bear on producing the task list — i.e.
  discourage over-decomposed waves and speculative tasks.
- **FR6.** `skills/verify/SKILL.md` references rule 4 (Goal-Driven Execution),
  framing the verify phase as the goal-check loop for the build.
- **FR7.** `CHANGELOG.md` gains a new `## [0.4.0] — 2026-05-20` section
  describing the addition.
- **FR8.** `plugins/specclaw/.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` both bump `version` from `0.3.3` to
  `0.4.0`.

### Non-Functional Requirements

- **NFR1.** Resilience: if `references/agent-guardrails.md` is missing at
  runtime, `specclaw-build-context` emits a warning to stderr and continues
  (does NOT abort the build). The agent payload simply lacks the guardrails
  section.
- **NFR2.** No new runtime dependencies. Pure bash + existing files.
- **NFR3.** Token budget: the guardrails reference stays under 100 lines / 2KB
  so the per-task prompt overhead is negligible.
- **NFR4.** Attribution & licensing: the reference file states upstream source
  and license (MIT, per the org's other repos — confirm during build).
- **NFR5.** Cross-platform: changes must not break the BSD/GNU sed portability
  already established in prior releases.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1.** `cat plugins/specclaw/references/agent-guardrails.md` returns a
  file whose first non-blank line begins with `# Agent Guardrails` (or
  similar header) and contains the four rule titles ("Think Before Coding",
  "Simplicity First", "Surgical Changes", "Goal-Driven Execution") verbatim
  from upstream.
- **AC2.** Running `bin/specclaw-build-context .specclaw karpathy-build-guardrails T1`
  (or any valid change+task) produces stdout that contains both:
  - the substring `Think Before Coding`, and
  - the substring `## Your Task`,
  with the guardrails appearing **before** `## Your Task`.
- **AC3.** Temporarily renaming `references/agent-guardrails.md` and re-running
  `specclaw-build-context` exits 0, prints a stderr warning containing
  "guardrails", and stdout still contains `## Your Task`.
- **AC4.** `grep -l "agent-guardrails.md" plugins/specclaw/skills/build/SKILL.md
  plugins/specclaw/skills/plan/SKILL.md plugins/specclaw/skills/verify/SKILL.md`
  lists all three files.
- **AC5.** `grep '"version"' plugins/specclaw/.claude-plugin/plugin.json
  .claude-plugin/marketplace.json` shows `0.4.0` in both.
- **AC6.** `head -20 CHANGELOG.md` shows a `## [0.4.0] — 2026-05-20` heading
  above `## [0.3.3]`.
- **AC7.** `bash -n bin/specclaw-build-context` succeeds (syntax check) and
  ShellCheck (if available) reports no new warnings on the modified script.

## Edge Cases

- **Missing guardrails file at build time** — handled by NFR1 (warn + continue).
- **Guardrails file contains backticks / special chars** — must not break the
  heredoc emission. Use a safe interpolation pattern (e.g. read into a
  variable, interpolate as `${GUARDRAILS}` inside the existing `cat <<PROMPT`).
- **First-time install of v0.4.0 over v0.3.3** — no data migration needed;
  references are read at runtime. Existing in-flight builds will pick up
  guardrails on the next agent spawn.
- **`SCRIPT_DIR` resolution under symlinks / plugin cache** — the guardrails
  path is computed relative to the script's own location
  (`$SCRIPT_DIR/../references/agent-guardrails.md`), matching how the script
  already locates `specclaw-parse-tasks`.

## Dependencies

- None new. Reuses existing bash + the script's existing path-resolution
  pattern.

## Notes

- Upstream source: https://github.com/multica-ai/andrej-karpathy-skills
- We are **vendoring** the text (not fetching at runtime) so builds work
  offline and aren't subject to upstream churn.
- Future work (out of scope here): consider per-skill guardrails (e.g.
  documentation-writing guardrails for `propose`), but only if a clear need
  emerges.
