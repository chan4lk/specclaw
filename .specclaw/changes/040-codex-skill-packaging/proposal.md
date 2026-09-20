# Proposal: Package SpecClaw as a Codex Skill Alongside Claude

**Created:** 2026-09-20
**Status:** 🟡 Draft

## Problem

This repository packages SpecClaw for Claude, but it is not yet directly consumable as a Codex skill. Maintaining a separate implementation would create drift and risk changing the existing Claude integration.

## Proposed Solution

Add Codex-skill packaging that reuses the existing SpecClaw skill content, templates, scripts, and lifecycle behavior. Keep the Claude skill and its packaging unchanged. Perform implementation in a dedicated Git worktree.

## Scope

### In Scope

- Create the Codex-facing skill entry point and metadata required for discovery.
- Reuse the existing SpecClaw skills, templates, binaries, and references rather than duplicating their implementation.
- Define paths and packaging so both Claude and Codex integrations continue to work independently.
- Create and use an isolated Git worktree for the implementation.
- Add focused verification for Codex-skill discovery and shared-resource resolution.

### Out of Scope

- Rewriting or relocating the existing Claude skill.
- Changing SpecClaw lifecycle semantics or the behavior of existing scripts.
- Publishing, installing, or modifying a user's global Codex skill configuration.

## Impact

- **Size:** bounded (spike / bounded / architectural)
- **Files affected:** 6–10 (estimated)
- **Complexity:** medium (small / medium / large)
- **Risk:** medium (low / medium / high)

## Open Questions

- Which repository-local Codex skill packaging convention best supports direct reuse of the existing Claude assets?
- What minimum discovery/validation test proves both integrations remain usable without duplicating content?

---

**To proceed:** Review this proposal and approve to begin planning.
