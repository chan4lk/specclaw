---
description: Backfill ordinal number prefixes onto existing change folders — renames .specclaw/changes/<name>/ to <NNN>-<name> in creation-date order, across active and archived changes alike. Use when /specclaw:status or /specclaw:propose reports unnumbered changes, when `ls .specclaw/changes/` reads alphabetically instead of chronologically, or when the user asks to number, renumber, or reorder change folders. Shows a dry-run plan and renames nothing without explicit confirmation.
---

# specclaw renumber

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Assign permanent `<NNN>-` prefixes to change folders that don't have them, so `ls` reads chronologically.

1. **Dry run:** `specclaw-renumber-changes .specclaw`. The tool is dry-run by default — without `--apply` it prints the plan and makes no filesystem modification whatsoever. If it prints nothing, every folder is already numbered; say so and stop.
2. Show the user the **full** `old → new` plan, every line of it, not a summary or a count. The plan is the only thing they have to judge before anything moves, and it covers both `changes/` and `changes/archive/`.
3. **Get explicit confirmation.** A "yes" to this plan and nothing weaker. Renaming is the one destructive operation in this skill; do not infer approval from a user asking a question about the plan.
4. **Apply:** re-run as `specclaw-renumber-changes .specclaw --apply`. Ordering is by creation date ascending, ties broken by folder name, so the applied result matches the plan the user just approved. After each rename the change's `state.json` is refreshed through `specclaw-set-phase` — the only writer of phase state.
5. Update the dashboard: `specclaw-update-status .specclaw`. The unnumbered-folders hint disappears once the backfill covers every folder.
6. Confirm the new names to the user.

## Refusals and `--force`

The tool refuses, before any rename, when a change is mid-build (a live worktree or checked-out branch still points at the old path), when a planned target path already exists, or when any folder is **already numbered**. Report the message and stop — each refusal names something the user must resolve first.

`--force` overrides only the already-numbered refusal, renumbering **every** folder from `001` in date order. Its one intended use is recovering from an interrupted `--apply`, which leaves a mixed part-numbered state that the ordinary run then declines to touch. Use it there and nowhere else: on a healthy repo it rewrites numbers that are already correct and already referenced from commit messages and branch names.
