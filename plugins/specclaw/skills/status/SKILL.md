---
description: Use when the user asks where changes stand or what is next.
---

**Flow check:** run `specclaw-ensure-init .specclaw && specclaw-flow .specclaw`. If it prints `full`, read `$CLAUDE_PLUGIN_ROOT/references/full/status.md` and follow it instead of this file.

# specclaw status

1. `specclaw-ensure-init .specclaw`, then `specclaw-update-status .specclaw`.
2. Present the file named in its `OK: Updated <path>` line (`.specclaw/STATUS.md` on an integration branch, a file inside `.git` on a change branch): active changes with progress, pending proposals, recently archived. Show any hint line verbatim.
3. For one change, run `specclaw-validate-change .specclaw <change> status`.
4. If `specclaw-check-update .specclaw` prints a line, show it verbatim.
5. **Tips:** run `specclaw-suggest .specclaw fleet` when two or more approved changes are not built yet, and `specclaw-suggest .specclaw dash`. For each, show any line it prints, at most once per session; if the user says no, run `specclaw-suggest .specclaw --dismiss <feature>`.
