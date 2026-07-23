# Proposal: specclaw learn — Capture Build Learnings

**Created:** 2026-03-28
**Status:** 🟡 Draft
**Inspired by:** self-improving-agent skill (LEARNINGS.md, promotion pipeline)

## Problem

After a build cycle, valuable knowledge emerges: which spec requirements were ambiguous, which design decisions worked/didn't, what patterns the agents discovered. Currently this knowledge evaporates when sessions end. The self-improving-agent captures structured learnings and promotes them — SpecClaw should do the same for build knowledge.

## Proposed Solution

Add a `specclaw learn` command and a `learnings.md` file per change:

```
.specclaw/changes/<change>/
├── learnings.md       ← NEW: structured build learnings
├── ...
```

### Two modes:

**1. Auto-capture (during build):**
After each wave completes, the build engine logs:
- Unexpected patterns agents discovered
- Spec gaps revealed during implementation
- Design decisions that needed adjustment

**2. Manual capture (`specclaw learn <change> "insight"`):**
User or agent can add a learning anytime. Useful during review or post-build reflection.

### Learning Entry Format

```markdown
## [L1] insight — Wave 2 agents needed shared type definitions

**When:** 2026-03-28 12:05 UTC
**Category:** spec_gap | design_gap | pattern | best_practice
**Priority:** medium

### Detail
Tasks T3 and T4 both needed a shared TypeSpec interface but the design
didn't account for this. T3 created it, T4 duplicated it.

### Action
Future specs should identify shared types as a Wave 1 task.

### Promoted
- [ ] → config.yaml defaults
- [ ] → SKILL.md agent instructions
- [ ] → Future proposal
```

### Promotion Pipeline

When a learning recurs across 3+ changes:
1. Flag it as `promote_candidate`
2. `specclaw learn promote` reviews candidates and suggests where to add them:
   - Agent prompt templates → better future agent context
   - SKILL.md → better orchestration instructions
   - config.yaml → better defaults
   - New proposal → systematic fix

## Scope

### In Scope
- `learnings.md` per change
- `specclaw learn <change> "<insight>"` manual capture
- Auto-capture hooks in build engine (post-wave summary)
- `specclaw learn promote` to review and elevate recurring learnings
- `scripts/log-learning.sh` helper

### Out of Scope
- ML-based pattern matching
- Integration with external knowledge bases
- Automatic code changes based on learnings

## Impact

- **Files affected:** ~5 (new script + template + SKILL.md + build engine hooks)
- **Complexity:** medium
- **Risk:** low — additive feature

## Open Questions

1. Should auto-capture happen after every wave or only after build completes?
2. How to detect "recurring" across changes — simple grep or structured tracking?

---

**To proceed:** Review this proposal and approve to begin planning.
