---
description: Inspect the cross-change pattern registry. Track recurring errors and learnings across changes; promote patterns with 3+ occurrences to prevention rules. Use to see what keeps happening before planning a new change.
---

# specclaw patterns

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

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

**Promote a pattern** to the repo-local knowledge base:
```bash
specclaw-detect-patterns .specclaw promote <pat-id>
```

Promote writes the prevention rule to `.specclaw/knowledge/agent-hints.md` — **never to the plugin itself**. The plugin stays versioned and generic; each repo builds its own knowledge over time.

**Auto-promotion:** patterns with 3+ occurrences are flagged ⚠️ — run `promote` to write their prevention rules into the local knowledge base so future build agents see them automatically.

Pattern registry lives at `.specclaw/patterns.md` (global, not per-change).
Knowledge base lives at `.specclaw/knowledge/` (repo-local, not plugin).
