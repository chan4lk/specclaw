# Proposal: specclaw pr — PR Creation Command

**Created:** 2026-05-13
**Status:** 🟡 Proposed

## Problem

After `specclaw verify` passes, there's no workflow step to create a GitHub PR. The lifecycle (`propose → plan → build → verify → archive`) has no PR creation gate — a developer could skip build/verify entirely and push an unverified branch to PR. There's also no way to auto-populate the PR body with spec and verification context.

## Proposed Solution

Add a `specclaw pr <change>` command that:

1. **Validates** via `validate-change.sh .specclaw <change> pr` — requires `verify-report.md` to exist, enforcing that build + verify must complete first.
2. **First-run test policy prompt** — on first invocation for a project (no `pr.test_policy` key in config), asks the operator: "Do you plan to implement automated tests (unit and/or e2e)?" Saves the answer to `config.yaml` under `pr.test_policy: none|unit|e2e|both`. Subsequent runs skip the prompt.
3. **Test enforcement** — if `pr.test_policy` is `unit`, `e2e`, or `both`, validates that `build.test_command` is configured and that the verify-report confirms tests ran (checks for test evidence in `verify-report.md`). Fails with a clear error if tests are missing.
4. **Extracts context** from `spec.md`, `verify-report.md`, and `proposal.md` to auto-populate the PR title and body.
5. **Runs `gh pr create`** with base `main`, a meaningful title, and a structured PR body (summary, acceptance criteria, verify verdict, test status).
6. **Saves the PR URL** into `status.md` for traceability.
7. **GitHub sync** (if enabled): links the PR to the GitHub Issue via a `Closes #N` reference in the body.

### New phase in validate-change.sh:

| Next Phase | Required Artifacts |
|---|---|
| `pr` | `verify-report.md` exists (implies build complete + verified) |

### Test policy in config.yaml:
```yaml
pr:
  test_policy: "none"   # none | unit | e2e | both
                        # Set on first `specclaw pr` run; enforced on all subsequent runs
```

### Usage:
```
specclaw pr <change>
# First run: prompts for test policy, saves to config, then creates PR
# Later runs: enforces test policy, then creates PR
```

## Scope

### In Scope
- `scripts/validate-change.sh`: add `pr` phase check (verify-report.md required)
- `scripts/pr.sh`: new script — first-run policy prompt, test enforcement, context extraction, `gh pr create`, saves PR URL
- `SKILL.md`: add `specclaw pr` command section
- `templates/config.yaml`: add `pr.test_policy` field with docs

### Out of Scope
- Actually running tests (that's `build.test_command` in the build phase)
- Enforcing CI/CD checks pass before merge (GitHub branch protection)
- Auto-merge after PR approval
- Multi-target PRs (always targets `main`)

## Open Questions
- Should `test_policy` be per-project (config.yaml) or per-change (status.md)? Proposal: **per-project** — test discipline is a project-wide decision.
- If `test_policy: unit` but verify-report has no test section, hard fail or warn? Proposal: **hard fail in strict mode, warn in non-strict** (same as existing `workflow.strict` pattern).

## Impact
- **Files affected:** 4 (`validate-change.sh`, new `pr.sh`, `SKILL.md`, `templates/config.yaml`)
- **Complexity:** small-medium
- **Risk:** low — additive only, no changes to existing phases
