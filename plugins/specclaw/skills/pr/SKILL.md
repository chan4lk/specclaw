---
description: Create a GitHub pull request for a verified change. Reads verify-report.md, opens a PR with title from proposal and body from spec, enforces the configured test policy. Requires the gh CLI authenticated. Run after /specclaw:verify produces a verify-report.md. For Azure DevOps PRs, use /specclaw:pr-azdo instead.
disable-model-invocation: true
---

# specclaw pr

Create a GitHub PR for a verified change. Requires `verify-report.md` (build + verify must complete first).

1. **Validate:** `specclaw-validate-change .specclaw <change> pr`. Exits with a warning (exit 0) if a PR already exists for this change. Fails if `verify-report.md` is missing.
2. **Run:** `specclaw-pr .specclaw <change>`
   - **First run:** prompts for test policy (`none|unit|e2e|both`), saves it to `config.yaml` under `pr.test_policy`. Never prompts again.
   - **Test enforcement:** if policy is not `none`, verifies `build.test_command` is set and that `verify-report.md` contains test evidence. Fails (strict) or warns (non-strict) if evidence is missing.
   - **PR creation:** builds title from `proposal.md`, body from `spec.md` + `verify-report.md`, runs `gh pr create --base main`.
   - **GitHub sync:** if `github.sync: true`, includes `Closes #N` in the PR body.
   - **Saves URL:** appends `**PR:** <url>` to `status.md`.
3. Report the PR URL to the user.
