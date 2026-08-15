# Proposal: Build Error Journal

**Created:** 2026-03-28
**Status:** 🟡 Draft
**Inspired by:** self-improving-agent skill (error-detector.sh, ERRORS.md)

## Problem

When a coding agent fails during `specclaw build`, we only get `[!] failed` in tasks.md and a brief note in status.md. The actual error context — what the agent tried, what went wrong, the error output — is lost once the agent session ends. This makes retries blind and debugging painful.

The self-improving-agent skill captures structured error entries with context, reproducibility notes, and suggested fixes. SpecClaw needs the same, but tailored to build failures.

## Proposed Solution

Auto-capture structured error entries when build tasks fail. Each change gets an `errors.md` file that accumulates across build attempts:

```
.specclaw/changes/<change>/
├── errors.md          ← NEW: structured build error journal
├── proposal.md
├── spec.md
├── design.md
├── tasks.md
└── status.md
```

When a task agent fails:
1. Extract error context from the agent's result (or timeout info)
2. Append a structured entry to `errors.md`
3. On retry, the build-context.sh feeds previous errors for this task to the new agent — so it doesn't repeat the same mistake

### Error Entry Format (lighter than self-improving-agent)

```markdown
## [T3] Wave 2 — Attempt 1

**When:** 2026-03-28 12:05 UTC
**Agent:** specclaw-feature-T3
**Runtime:** acp | Model: codex

### What Failed
Brief description from agent result

### Error Output
```
actual error or timeout info
```

### Context
- Files attempted: src/auth.ts, src/middleware.ts
- Previous task outputs available: T1 ✅, T2 ✅

### Resolution
- **Status:** pending | resolved_on_retry | wont_fix
- **Retry:** Attempt 2 succeeded — agent needed existing import pattern
```

## Scope

### In Scope
- Auto-capture errors during `specclaw build` when tasks fail
- Structured `errors.md` per change
- Feed previous errors as context on retry (avoid repeating mistakes)
- Script to append error entries (`scripts/log-error.sh`)
- Update build-context.sh to include error history for retried tasks

### Out of Scope
- Cross-change error pattern detection (separate proposal: pattern-detection)
- Manual error logging outside builds
- Integration with external error tracking systems

## Impact

- **Files affected:** ~4 (new script + template + modify build-context.sh + SKILL.md)
- **Complexity:** small
- **Risk:** low — additive feature, doesn't change existing build flow

## Open Questions

1. How many previous error entries to include in retry context? (suggest: last 3 per task)
2. Should errors.md be auto-cleaned on successful completion, or kept as history?

---

**To proceed:** Review this proposal and approve to begin planning.
