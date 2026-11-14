# Tasks: {{title}}

**Change:** {{change_name}}
**Created:** {{date}}
**Total Tasks:** {{task_count}}

## Summary

{{summary}}

## Tasks

### Wave 1 — {{wave_1_description}}

{{wave_1_tasks}}

### Wave 2 — {{wave_2_description}}

{{wave_2_tasks}}

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred — correctly blocked on a sibling change, not incomplete through any fault of its own; excluded from the incomplete-task count that gates `verify`

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Kind: frontend | backend | docs | test | config | refactor | impl | migration   (optional; routes the build agent, see budget.routing)
  - Context: <tokens the task's agent will hold>   (from `specclaw-budget estimate`; over 60000 means split the task)
  - Depends: <task ids> (if any)
  - Notes: <additional context>
  - Deferred-Reason: <why this can't be built yet>            (required when marker is `[>]`)
  - Deferred-Blocked-On: <sibling change name, if known>      (optional; free text, not a structured link)
```

The optional `Kind` hint picks the build agent through `budget.routing`
(`frontend` and `docs` go to `builder-frontend` on Sonnet, anything else to
`builder-backend` on Opus), and is consumed by `build.dynamic_agents` (when
enabled) to synthesize a specialized subagent per task. `Context` becomes the
task's launch budget (`specclaw-budget brief`).
