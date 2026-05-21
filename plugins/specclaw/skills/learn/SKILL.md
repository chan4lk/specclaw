---
description: Record a build learning — a spec gap, design miss, recurring pattern, or insight discovered during implementation. Appends to .specclaw/changes/<change>/learnings.md. Use mid-build to capture knowledge before it's lost; do not use for routine progress updates.
---

# specclaw learn

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

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

**Promote a learning** to the repo-local knowledge base:
```bash
specclaw-log-learning .specclaw <change> --promote <id>
```

Promote writes to `.specclaw/knowledge/` — **never to the plugin itself**:
- `spec_gap`, `design_gap` → `.specclaw/knowledge/spec-guidelines.md`
- `pattern`, `best_practice`, `agent_issue` → `.specclaw/knowledge/agent-hints.md`

The build agent receives `agent-hints.md` as context automatically on every task.

**When to log:**
- A build revealed a spec gap (requirements unclear or missing)
- A design decision needed mid-build adjustment
- Agents discovered a useful pattern worth reusing
- Parallel tasks created conflicts (duplicate code, shared deps)
- An agent struggled with the context or instructions

Learnings are stored in `.specclaw/changes/<change>/learnings.md` and feed the pattern detection system for cross-change analysis (see `/specclaw:patterns`).
