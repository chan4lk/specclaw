---
description: Inspect the cross-change pattern registry. Track recurring errors and learnings across changes; promote patterns with 3+ occurrences to prevention rules. Use to see what keeps happening before planning a new change.
disable-model-invocation: true
---

# specclaw patterns

Track recurring patterns across changes — errors and learnings that repeat become prevention rules.

**Scan a change for patterns:**
```bash
specclaw-detect-patterns .specclaw scan <change>
```
Reads `errors.md` and `learnings.md`, matches against existing patterns, creates new ones or increments existing.

**List all patterns:**
```bash
specclaw-detect-patterns .specclaw list [--min-recurrence N]
```

**Promote a pattern** (mark for elevation to agent prompts):
```bash
specclaw-detect-patterns .specclaw promote <pat-id>
```

**Auto-promotion:** patterns with 3+ occurrences are flagged ⚠️ — their prevention rules should be added to agent context templates or to the relevant SKILL.md build instructions.

Pattern registry lives at `.specclaw/patterns.md` (global, not per-change).
