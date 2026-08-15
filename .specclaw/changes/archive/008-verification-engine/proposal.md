# Proposal: Verification Engine

**Created:** 2026-03-28
**Status:** 🟢 Approved

## Problem

SpecClaw can propose, plan, and build — but can't verify. After `specclaw build` completes, there's no automated way to check whether the implementation actually satisfies the spec's acceptance criteria. The agent-prompts.md has a Verify Agent template, but no script infrastructure to drive it.

## Proposed Solution

Implement `specclaw verify <change>` as a structured verification pipeline:

1. **Collect evidence:** Read spec.md acceptance criteria, gather changed files, run configured tests
2. **Spawn verify agent:** Pass spec + implementation to a review model (Sonnet by default)
3. **Generate report:** Structured pass/fail per acceptance criterion
4. **Update status:** Mark change as verified/failed in status.md
5. **Run commands:** Execute test_command, lint_command, build_command if configured
6. **Notify:** Post results to GitHub issue and notifications channel

### Verification Report Format (in verify-report.md):

```markdown
# Verification Report: <change-name>

**Verified:** 2026-03-28 14:00 UTC
**Model:** anthropic/claude-sonnet-4-5
**Verdict:** PASS | FAIL | PARTIAL

## Acceptance Criteria

- ✅ **AC-1:** GIVEN valid tasks.md WHEN parse-tasks.sh runs THEN outputs valid JSON — **PASS** (tested with 3 sample files)
- ❌ **AC-2:** GIVEN parallel_tasks: 2 WHEN building THEN spawns 2 at a time — **FAIL** (no batching logic found)

## Test Results

```
$ npm test
All 12 tests passed
```

## Issues Found

1. AC-2: Batching not implemented — tasks spawn all at once regardless of limit

## Summary

**Passed:** 8/10 criteria
**Failed:** 2/10 criteria
**Verdict:** PARTIAL
```

## Scope

### In Scope
- `scripts/verify.sh` — collect changed files, run test/lint/build commands, output results
- Verify Agent prompt construction (from spec + changed files + test output)
- Structured report generation (verify-report.md per change)
- Status updates (status.md, STATUS.md dashboard)
- SKILL.md `specclaw verify` detailed execution flow
- GitHub issue comment with results
- Support for `automation.auto_verify: true` (trigger after build)

### Out of Scope
- Auto-fix failed criteria (that's a re-plan → re-build cycle)
- Security scanning
- Performance benchmarking

## Impact

- **Files affected:** ~5 (new script, report template, SKILL.md, status updates)
- **Complexity:** medium
- **Risk:** low — additive, reads existing artifacts
