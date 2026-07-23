# Proposal: Phase Validation Guards

**Created:** 2026-03-28
**Status:** 🟢 Approved

## Problem

We skipped the proposal for git-worktrees and gh-sync.sh broke because it expects proposal.md. There's no enforcement of phase prerequisites — you can jump straight to build without a spec, or verify without completing tasks. This defeats the purpose of spec-driven development.

## Proposed Solution

A `validate-change.sh` script that checks prerequisites before each phase transition. The agent calls it at the start of every command. If validation fails, the agent stops and reports what's missing.

### Phase prerequisites:

| Next Phase | Required Artifacts |
|---|---|
| `plan` | proposal.md exists |
| `build` | spec.md + design.md + tasks.md exist |
| `verify` | all tasks [x] complete (no pending/in_progress) |
| `archive` | verify-report.md exists |
| `github-create` | proposal.md exists (when github.sync is true) |

### Usage:
```
validate-change.sh <specclaw_dir> <change_name> <phase>
# Exit 0 = ready, Exit 1 = missing prerequisites (listed to stderr)
```

## Scope

### In Scope
- `scripts/validate-change.sh` with all phase checks
- SKILL.md: add validation call at start of plan/build/verify/archive commands
- Configurable strict mode: `workflow.strict: true` (default true, can disable for rapid prototyping)

### Out of Scope
- Git hooks (too invasive)
- Blocking at the git level

## Impact
- **Files affected:** 3 (new script, SKILL.md, config template)
- **Complexity:** small
- **Risk:** low
