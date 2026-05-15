---
description: Show the project's specclaw dashboard — active changes, completed changes, pending proposals, blocked work. Reads .specclaw/STATUS.md. Read-only; does not modify state.
disable-model-invocation: true
---

# specclaw status

Show the project dashboard.

1. Refresh: `specclaw-update-status .specclaw`
2. Read `.specclaw/STATUS.md` and present:
   - Active changes with progress %
   - Pending proposals
   - Recently archived changes
   - Overall project health
3. For a specific change, run `specclaw-validate-change .specclaw <change> status` to get a per-change snapshot.
