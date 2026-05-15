---
description: Record a build learning — a spec gap, design miss, recurring pattern, or insight discovered during implementation. Appends to .specclaw/changes/<change>/learnings.md. Use mid-build to capture knowledge before it's lost; do not use for routine progress updates.
disable-model-invocation: true
---

# specclaw learn

Capture build learnings — spec gaps, design misses, and patterns discovered during implementation.

**Log a learning:**
```bash
specclaw-log-learning .specclaw <change> <category> <priority> "<detail>" ["<action>"]
```

Categories: `spec_gap` | `design_gap` | `pattern` | `best_practice` | `agent_issue`
Priorities: `low` | `medium` | `high`

**List learnings for a change:**
```bash
specclaw-log-learning .specclaw <change> --list
```

**Promote a learning** (mark for elevation to agent prompts or this SKILL):
```bash
specclaw-log-learning .specclaw <change> --promote <id>
```

**When to log:**
- A build revealed a spec gap (requirements unclear or missing)
- A design decision needed mid-build adjustment
- Agents discovered a useful pattern worth reusing
- Parallel tasks created conflicts (duplicate code, shared deps)
- An agent struggled with the context or instructions

Learnings are stored in `.specclaw/changes/<change>/learnings.md` and feed the pattern detection system for cross-change analysis (see `/specclaw:patterns`).
