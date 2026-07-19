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

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Kind: docs | test | config | refactor | impl | migration   (optional; hints the build subagent's role, tools, and model)
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```

The optional `Kind` hint is consumed by `build.dynamic_agents` (when enabled) to
synthesize a specialized subagent per task. Omit it and build classifies
heuristically, defaulting to `impl`.
