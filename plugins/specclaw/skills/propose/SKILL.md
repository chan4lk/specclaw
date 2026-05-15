---
description: Draft a new change proposal. Creates .specclaw/changes/<name>/proposal.md with problem statement, solution, scope, impact, and open questions. The first step in the propose → plan → build → verify → pr lifecycle. Use when the user wants to record a feature idea or initiative before writing any spec.
---

# specclaw propose

Create a new proposal for a change.

1. Slugify the user's idea into a `<change-name>` (lowercase, hyphens, no spaces).
2. Create `.specclaw/changes/<change-name>/`.
3. Generate `proposal.md` from `$CLAUDE_PLUGIN_ROOT/templates/proposal.md`. Fill in: problem statement, proposed solution, scope (in / out), impact (files, complexity, risk), open questions.
4. Present the proposal to the user for review.
5. Update `.specclaw/STATUS.md` via `specclaw-update-status .specclaw`.
6. **GitHub sync** (if `github.sync: true` in `config.yaml`): run `specclaw-gh-sync create .specclaw <change-name>` to create a GitHub Issue for the proposal. Validation (proposal.md must exist) is enforced by `specclaw-validate-change`.

Do not proceed to `/specclaw:plan` until the user has approved the proposal.
