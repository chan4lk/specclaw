---
description: Move a completed change to .specclaw/changes/archive/ under its existing name. Closes the GitHub Issue (if sync is enabled) and optionally creates a git tag. Use after a change is merged — the PR is complete and the change should leave the active list.
---

# specclaw archive

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Archive a completed change.

1. **Validate:** `specclaw-validate-change .specclaw <change> archive`. If it fails, report and stop.
2. Verify the change is complete (all tasks done, verification passed, PR merged).
3. Record the phase: `specclaw-set-phase .specclaw <change> archived done`. `specclaw-set-phase` is the only writer of phase state — it records `state.json` and upserts the Archived row in `status.md`. Never hand-edit those rows. Run it **before** the move, so the recorded state travels with the directory.
4. Move to `.specclaw/changes/archive/<change>/` — the name is preserved verbatim, number included, with no date prefix. The leading `<NNN>-` already orders the folder, and the archive date is recorded in `state.json` by step 3; the old prefix was the *archive* date, not the change's, so a single bulk archival run stamped 24 of this repo's folders with one identical date — ordering by it was actively misleading.
5. Update the dashboard: `specclaw-update-status .specclaw`.
6. **GitHub sync** (if enabled): `specclaw-gh-sync close .specclaw <change>` to close the issue.
7. **Azure Boards sync** (if `azdo.boards.sync: true`): `specclaw-azdo-issue close .specclaw <change>` to post a closing comment and add a `closed-by-specclaw` tag. (Does not transition Work Item state — humans drive state in ADO.)
8. Optionally create a git tag for the release.
