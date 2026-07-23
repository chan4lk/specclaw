# Proposal: GitHub Issues Sync

**Created:** 2026-03-28
**Status:** 🟢 Approved

## Problem

SpecClaw tracks everything locally in markdown — invisible to the team. GitHub Issues gives visibility, comments, and linkability.

## Proposed Solution (Simplified)

**One GitHub Issue per change** (epic/feature level). Tasks are a checklist inside the issue body, updated as the build progresses. No per-task issues, no JSON tracking file.

### What gets synced:

| SpecClaw Event | GitHub Action |
|---|---|
| `specclaw propose` | Create issue with proposal content + `specclaw` label |
| `specclaw plan` | Update issue body with task checklist from tasks.md |
| `specclaw build` (task complete) | Check off task in issue body, add progress comment |
| `specclaw build` (task failed) | Add error comment to issue |
| `specclaw verify` | Add verification result comment |
| `specclaw archive` | Close issue with completion comment |

### Issue body format:

```markdown
## 🦞 SpecClaw: Add dark mode

**Change:** `add-dark-mode`
**Status:** Building (3/6 tasks)

### Proposal
<proposal.md content summary>

### Tasks
- [x] T1 — Create theme context provider (Wave 1)
- [x] T2 — Add CSS custom properties (Wave 1)
- [x] T3 — Create toggle component (Wave 2)
- [ ] T4 — Integration tests (Wave 3)

### Spec
<link to spec.md in repo or inline summary>

---
*Managed by [SpecClaw](https://github.com/chanbistec/specclaw)*
```

### Issue number storage:

Just add `**GitHub Issue:** #42` to the change's `status.md`. No separate tracking file needed.

## Implementation

Script `scripts/gh-sync.sh` supporting both `gh` CLI and curl + GitHub token:

- `gh-sync.sh create <specclaw_dir> <change>` — Create issue from proposal
- `gh-sync.sh update <specclaw_dir> <change>` — Update issue body with current task status
- `gh-sync.sh comment <specclaw_dir> <change> "<text>"` — Add comment (errors, learnings, verify results)
- `gh-sync.sh close <specclaw_dir> <change>` — Close issue with completion note
- `gh-sync.sh setup` — Create `specclaw` label if missing, verify auth

Auth detection order: `gh` CLI → `GITHUB_TOKEN` env → config.yaml `github.token`

## Configuration

```yaml
github:
  sync: false                   # Enable GitHub sync
  repo: ""                      # Auto-detect from git remote if empty
  token: ""                     # PAT for curl fallback (optional if gh CLI authed)
  label: "specclaw"             # Label for issues
```

## Scope

### In Scope
- `gh-sync.sh` with create/update/comment/close/setup
- Both `gh` CLI and curl + token support
- One issue per change with task checklist
- Issue number in status.md
- Config additions
- SKILL.md integration hooks

### Out of Scope
- Per-task issues, milestones, projects boards
- Bidirectional sync
- Non-GitHub providers

## Impact

- **Files affected:** ~4 (new script, config template, SKILL.md, status template)
- **Complexity:** medium
- **Risk:** low — additive, opt-in via config

---

**To proceed:** Approved — plan and build.
