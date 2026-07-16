---
description: Show the project's specclaw dashboard — active changes, completed changes, pending proposals, blocked work. Reads .specclaw/STATUS.md. Read-only; does not modify state.
---

# specclaw status

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Show the project dashboard.

1. Refresh: `specclaw-update-status .specclaw`
2. Read `.specclaw/STATUS.md` and present:
   - Active changes with progress %
   - Pending proposals
   - Recently archived changes
   - Overall project health
3. For a specific change, run `specclaw-validate-change .specclaw <change> status` to get a per-change snapshot.
4. **Update check:** run `specclaw-check-update .specclaw`. If it prints a line (a newer plugin version is published), show that line verbatim after the dashboard; if it prints nothing, say nothing. The script is fail-silent and gated by `plugin.update_check` in config.yaml — never treat its absence of output as an error.
