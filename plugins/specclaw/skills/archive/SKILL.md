---
description: Move a completed change to .specclaw/changes/archive/ with a date prefix. Closes the GitHub Issue (if sync is enabled) and optionally creates a git tag. Use after a change is merged — the PR is complete and the change should leave the active list.
---

# specclaw archive

Archive a completed change.

1. **Validate:** `specclaw-validate-change .specclaw <change> archive`. If it fails, report and stop.
2. Verify the change is complete (all tasks done, verification passed, PR merged).
3. Move to `.specclaw/changes/archive/YYYY-MM-DD-<change>/`.
4. Update the dashboard: `specclaw-update-status .specclaw`.
5. **GitHub sync** (if enabled): `specclaw-gh-sync close .specclaw <change>` to close the issue.
6. Optionally create a git tag for the release.
