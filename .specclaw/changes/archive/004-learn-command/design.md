# Design: specclaw learn

**Change:** learn-command
**Created:** 2026-03-28

## Technical Approach

Single script `log-learning.sh` handles logging, listing, and promoting. SKILL.md gets `specclaw learn` command docs.

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `skill/scripts/log-learning.sh` | **Create** | Log, list, promote learnings |
| `skill/templates/learnings.md` | **Create** | Template header for learnings.md |
| `skill/SKILL.md` | **Modify** | Add specclaw learn command documentation |

## Learning Entry Format

```markdown
## [L1] spec_gap — Tasks needed shared type definitions

**When:** 2026-03-28 14:00 UTC
**Category:** spec_gap
**Priority:** medium
**Status:** pending | promoted

### Detail
Wave 2 agents T3 and T4 both created duplicate TypeSpec interfaces...

### Action
Future specs should identify shared types as Wave 1 tasks.

---
```

## Key Decisions

1. **Sequential IDs (L1, L2, L3)** — simpler than timestamps, easy to reference
2. **Five categories** — focused on build-relevant insights, not general knowledge
3. **Promote marks status only** — actual promotion to SKILL.md/prompts is manual (pattern-detection will automate later)
