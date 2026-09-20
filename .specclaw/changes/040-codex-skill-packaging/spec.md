# Spec: Package SpecClaw as a Codex Skill Alongside Claude

**Change:** 040-codex-skill-packaging
**Created:** 2026-09-20
**Status:** 🟡 Draft

## Overview

Expose SpecClaw as one repository-local Codex skill without creating a second lifecycle implementation. The Codex entry point will route requests to the canonical skill documents and executables under `plugins/specclaw/`; the existing Claude Code marketplace package remains untouched.

## Requirements

### Functional Requirements

- **FR1** — Add one Codex-discoverable entry point at `.agents/skills/specclaw/SKILL.md` with valid `name` and discriminating `description` frontmatter.
- **FR2** — The entry point SHALL resolve the repository's canonical plugin root and route lifecycle requests to the corresponding existing `plugins/specclaw/skills/<verb>/SKILL.md`; it SHALL not copy or fork lifecycle instructions.
- **FR3** — The entry point SHALL instruct Codex to invoke helpers through the canonical `plugins/specclaw/bin/` path and to resolve Claude-root references against that same canonical plugin root.
- **FR4** — The routing instructions SHALL cover the existing lifecycle skill directories dynamically or enumerate only targets that exist, so every documented target is resolvable.
- **FR5** — Add repository documentation explaining Codex repository-local discovery and how to invoke SpecClaw from a checkout, while retaining the existing Claude Code installation and command documentation.
- **FR6** — Add an automated validation that checks the Codex entry point, canonical target resolution, non-duplication of lifecycle instructions, and CI registration.

### Non-Functional Requirements

- **NFR1** — No existing file under `plugins/specclaw/.claude-plugin/`, `.claude-plugin/`, or `plugins/specclaw/skills/` may be modified for this change.
- **NFR2** — The Codex adapter SHALL add no runtime dependency beyond tools already used by this repository (`git`, Bash, and the existing scripts).
- **NFR3** — Validation SHALL be offline, deterministic, and complete in under five seconds on a normal checkout.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1** — Starting Codex from the repository root discovers `.agents/skills/specclaw/SKILL.md` as a valid skill with `name: specclaw` and a non-empty description.
- **AC2** — The adapter provides a reproducible repository-root/plugin-root resolution and maps each requested SpecClaw verb to an existing canonical `plugins/specclaw/skills/<verb>/SKILL.md`.
- **AC3** — Commands issued from the adapter resolve existing helpers from `plugins/specclaw/bin/`; no copied helper or template tree exists below `.agents/skills/specclaw/`.
- **AC4** — The adapter preserves the existing lifecycle's Claude-root resource semantics by resolving those references to the canonical plugin root.
- **AC5** — The Claude marketplace manifest, Claude plugin manifest, and canonical Claude skill documents are byte-identical to their pre-change versions.
- **AC6** — The Codex skill validation passes locally and is registered in `.github/workflows/ci.yml`.
- **AC7** — README and documentation contain both a Codex repository-local usage path and the unchanged Claude Code installation path.

## Edge Cases

- A lifecycle request names an unavailable verb: the adapter must stop and report that the canonical skill directory is absent rather than inventing a workflow.
- Codex is started outside this repository: the repository-local adapter is not discovered; documentation must state that this packaging is checkout-local and does not install global skills.
- A future lifecycle skill is added: dynamic target resolution must discover it without requiring a duplicated Codex copy.

## Dependencies

- Existing canonical assets: `plugins/specclaw/skills/`, `plugins/specclaw/bin/`, `plugins/specclaw/templates/`, and `plugins/specclaw/references/`.
- Codex repository-local skill discovery at `.agents/skills/`, as documented by OpenAI.

## Approach

- Create only `.agents/skills/specclaw/SKILL.md` as the Codex adapter.
- Resolve the checkout root at use time, then use `plugins/specclaw/` as the sole canonical asset root.
- Route each request into the original verb skill; call helpers by their canonical `bin/` path.
- Add one focused shell validator and register it in CI.
- Document checkout-local Codex use alongside, not in place of, Claude plugin installation.

## Notes

### Grounding sources

- `docs/index.md:122-136` describes the existing single canonical plugin location: “The specclaw plugin lives at `plugins/specclaw/`” and states that scripts resolve internal resources via `$CLAUDE_PLUGIN_ROOT`; the adapter therefore resolves all resources from that location rather than duplicating them.
- `CONTRIBUTING.md:33-40` says “The plugin lives in `plugins/specclaw/` (skills, agents, templates, references, tests)” and validates it from a checkout; the Codex path is likewise intentionally repository-local.
- [OpenAI’s Build skills documentation](https://developers.openai.com/docs/build-skills) specifies `.agents/skills` as Codex’s repository-skill location and supports symlinked skill folders; this change uses the repository convention while retaining a small adapter for the existing multi-verb layout.
