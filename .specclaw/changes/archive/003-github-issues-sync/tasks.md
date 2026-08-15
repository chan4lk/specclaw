# Tasks: GitHub Issues Sync

**Change:** github-issues-sync
**Created:** 2026-03-28
**Total Tasks:** 3

## Summary

Create gh-sync.sh with dual gh/curl support, update config template, update SKILL.md.

## Tasks

### Wave 1 — Core script

- [x] `T1` — Create gh-sync.sh with create/update/comment/close/setup subcommands
  - Files: skill/scripts/gh-sync.sh
  - Estimate: medium
  - Notes: Auth detection: try `gh` CLI first, fall back to curl + GITHUB_TOKEN env or config token. Auto-detect repo from `git remote get-url origin` if not in config. Subcommands: (1) setup — create "specclaw" label if missing. (2) create <specclaw_dir> <change> — read proposal.md, build issue body with proposal summary + empty task checklist (if tasks.md exists), create issue via gh/curl, extract issue number, append "**GitHub Issue:** #N" to status.md. (3) update <specclaw_dir> <change> — read issue number from status.md, read tasks.md, rebuild task checklist with current statuses ([x] complete, [ ] pending/in_progress/failed), update issue body via gh/curl. (4) comment <specclaw_dir> <change> "<text>" — add comment to the issue. (5) close <specclaw_dir> <change> — close issue with "✅ Change completed and archived" comment. For curl: use GitHub REST API v3 (repos/{owner}/{repo}/issues). Parse owner/repo from git remote URL (SSH or HTTPS format). Include --help, set -euo pipefail, executable.

### Wave 2 — Integration

- [x] `T2` — Add github sync config to config.yaml template
  - Files: skill/templates/config.yaml
  - Depends: T1
  - Estimate: small
  - Notes: Add github section with sync (bool, default false), repo (string, auto-detect), token (string, optional), label (string, default "specclaw"). Add comments explaining each field.

- [x] `T3` — Hook gh-sync into SKILL.md workflow commands
  - Files: skill/SKILL.md
  - Depends: T1
  - Estimate: small
  - Notes: Add sync calls (gated on github.sync config) to: propose (gh-sync.sh create after proposal created), plan (gh-sync.sh update after tasks generated), build (gh-sync.sh update after each wave, gh-sync.sh comment on errors), verify (gh-sync.sh comment with results), archive (gh-sync.sh close). Keep additions minimal — one line per hook point. Add note about gh CLI or GITHUB_TOKEN requirement.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
