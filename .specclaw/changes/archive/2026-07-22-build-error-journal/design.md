# Design: Build Error Journal

**Change:** build-error-journal
**Created:** 2026-03-28

## Technical Approach

Add a `log-error.sh` script that appends structured error entries to `errors.md`. Modify `build-context.sh` to read previous errors and inject them into retry context. The build engine (SKILL.md) calls log-error.sh when a task fails, and calls it with "resolved" when a retry succeeds.

## Architecture

```
Task fails → Agent orchestrator calls log-error.sh → Appends to errors.md
Task retried → build-context.sh reads errors.md → Injects "Previous Errors" section
Task succeeds after failure → log-error.sh --resolve marks entries resolved
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `skill/scripts/log-error.sh` | **Create** | Append structured error entries to errors.md |
| `skill/scripts/build-context.sh` | **Modify** | Read errors.md and inject previous errors for retried tasks |
| `skill/templates/errors.md` | **Create** | Template header for errors.md |
| `skill/SKILL.md` | **Modify** | Add error logging calls in build failure handling |

## Data Model Changes

### Error Entry Format

```markdown
## [T3] Attempt 1 — Wave 2

**When:** 2026-03-28 12:05 UTC
**Agent:** specclaw-change-T3
**Status:** pending | resolved_on_retry

### Summary
Brief description of failure

### Error Output
\`\`\`
actual error text (truncated to 50 lines)
\`\`\`

### Context
- Files: src/auth.ts, src/middleware.ts
- Depends: T1 ✅, T2 ✅

---
```

## Key Decisions

1. **Append-only during builds** — never delete error entries during a build run. Mark resolved instead.
2. **Last 3 per task in context** — enough history to be useful, not enough to bloat context.
3. **50-line error output cap** — prevents massive stack traces from eating context window.
4. **errors.md only created on first failure** — no empty files cluttering clean builds.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Error output too large | Cap at 50 lines in log-error.sh |
| Too many retries bloat errors.md | build-context.sh only reads last 3 per task |
| Script called with missing args | Validate all args, show usage |
