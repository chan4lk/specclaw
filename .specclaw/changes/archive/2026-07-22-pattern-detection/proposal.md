# Proposal: Cross-Change Pattern Detection

**Created:** 2026-03-28
**Status:** 🟡 Draft
**Inspired by:** self-improving-agent skill (Pattern-Key, Recurrence-Count, Simplify & Harden Feed)

## Problem

Build failures and learnings repeat across changes. "Agent forgot to handle imports" happens in change A, then again in change B, then again in change C — but nobody connects the dots. The self-improving-agent uses Pattern-Key tracking and recurrence counting to detect this. SpecClaw needs the same but focused on build patterns.

## Proposed Solution

Add a global pattern registry at `.specclaw/patterns.md` that tracks recurring themes across changes:

```
.specclaw/
├── patterns.md        ← NEW: cross-change pattern registry
├── config.yaml
├── STATUS.md
└── changes/
```

### How it works:

1. **Detection:** After each build, scan `errors.md` and `learnings.md` for patterns similar to existing entries (keyword matching + category)
2. **Registration:** New patterns get a `Pattern-Key` and `Recurrence-Count: 1`
3. **Tracking:** When the same pattern appears in another change, increment count and link
4. **Auto-promotion (threshold: 3 occurrences):** Pattern gets promoted to agent context:
   - Add to `references/agent-prompts.md` Build Agent constraints
   - Add to SKILL.md build instructions
   - Optionally add to config.yaml as a custom constraint

### Pattern Entry Format

```markdown
## [PAT-001] agents-forget-shared-types

**First Seen:** 2026-03-28 (build-engine)
**Last Seen:** 2026-04-02 (auth-module)
**Recurrence:** 3
**Status:** active | promoted | resolved

### Pattern
Coding agents in parallel waves create duplicate type definitions
instead of using shared ones from earlier waves.

### Occurrences
- `build-engine` L1 — T3/T4 duplicated interfaces
- `auth-module` L2 — T2/T3 duplicated user types
- `dashboard` L1 — T1/T2 duplicated API types

### Prevention Rule
> When planning tasks, identify shared types/interfaces as explicit
> Wave 1 tasks. Reference them in dependent task context.

### Promoted To
- [x] agent-prompts.md Build Agent constraints
- [ ] SKILL.md planning instructions
```

## Scope

### In Scope
- Global `patterns.md` registry
- `specclaw patterns` command to view and manage patterns
- Auto-detection: scan errors.md/learnings.md after builds
- Recurrence counting and cross-change linking
- Auto-promotion at threshold (configurable, default: 3)
- Script: `scripts/detect-patterns.sh`

### Out of Scope
- NLP/semantic matching (use keyword + category matching)
- External pattern databases
- Auto-modifying agent code based on patterns

## Impact

- **Files affected:** ~5 (new script + patterns.md + SKILL.md + build hooks)
- **Complexity:** medium
- **Risk:** low — additive, read-only analysis of existing data

## Open Questions

1. Should pattern matching be purely keyword-based or use simple fuzzy matching?
2. What's the right recurrence threshold for auto-promotion? (3 seems reasonable)
3. Should promoted patterns be injected into every build, or only for related changes?

---

**To proceed:** Review this proposal and approve to begin planning.
