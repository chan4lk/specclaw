# Proposal: Post-Build Review Prompt

**Created:** 2026-03-28
**Status:** 🟡 Draft
**Inspired by:** self-improving-agent skill (activator.sh hook)

## Problem

The self-improving-agent injects a ~50-token review prompt after each task asking: "Did anything non-obvious happen? Log it." This lightweight nudge catches learnings that would otherwise be lost. SpecClaw has no equivalent — builds complete and move on without reflection.

## Proposed Solution

After `specclaw build` completes (or partially completes with failures), inject a structured review step:

### Auto-Review (lightweight, ~100 tokens)

The build engine, after finalize, prompts the orchestrating agent:

```
🦞 Build Review — <change-name>
Results: 5/6 tasks passed, 1 failed

Quick check:
1. Any spec requirements that were unclear to agents?
2. Any design decisions that needed adjustment mid-build?
3. Any files that multiple agents touched unexpectedly?
4. Any patterns worth capturing for future builds?

Log insights with: specclaw learn <change> "<insight>"
```

### Verification-Integrated Review

When `specclaw verify` runs after build, it also checks:
- Did the implementation deviate from the spec? If so, was the spec wrong or the implementation?
- Were there any files changed outside declared task scope?
- Did any acceptance criteria need reinterpretation?

These findings auto-feed into `learnings.md`.

## Scope

### In Scope
- Post-build review prompt in SKILL.md build flow
- Scope deviation detection (files changed vs. files declared in tasks)
- Auto-log review findings to `learnings.md`
- Configurable: `automation.post_build_review: true|false` in config.yaml

### Out of Scope
- AI-powered code review (that's verify's job)
- Performance profiling
- Cost analysis per build

## Impact

- **Files affected:** ~3 (SKILL.md build flow, config.yaml template, verify integration)
- **Complexity:** small
- **Risk:** low — it's a prompt addition, not a code change

## Open Questions

1. Should review be automatic or opt-in? (suggest: automatic, configurable off)
2. Should scope deviation (files outside declared list) block the build or just warn?

---

**To proceed:** Review this proposal and approve to begin planning.
