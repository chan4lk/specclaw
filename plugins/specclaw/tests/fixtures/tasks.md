# Tasks: Fixture Change — Parser Regression

**Change:** fixture-change
**Created:** 2026-06-14
**Total Tasks:** 3

## Summary

Template-shaped tasks.md used to lock in B2 (fence/legend exclusion) and B4 (bulleted Files: lines).

## Tasks

### Wave 1 — Foundation

- [x] `T1` — Real complete task
  - Files: `src/a.ts`, `src/b.ts`
  - Estimate: small
  - Notes: Done.

- [ ] `T2` — Real pending task
  - Files: `src/c.ts`
  - Estimate: medium

### Wave 2 — Integration

- [~] `T3` — Real in-progress task
  - Files: `src/d.ts`
  - Depends: T1, T2
  - Estimate: large

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
