---
name: specclaw
description: Run the SpecClaw spec-driven lifecycle in this repository when a request needs proposal, planning, build, verification, PR, or lifecycle-status work.
---

# SpecClaw

Use the canonical SpecClaw implementation in this checkout. This is a Codex
adapter only: do not copy, rewrite, or fork the lifecycle skills, scripts,
templates, or references.

## Resolve the canonical plugin

Before routing a lifecycle request, resolve the repository and plugin roots:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SPECCLAW_PLUGIN_ROOT="$REPO_ROOT/plugins/specclaw"
```

Confirm that `$SPECCLAW_PLUGIN_ROOT/skills/` and
`$SPECCLAW_PLUGIN_ROOT/bin/` exist. If either is absent, report that the
checkout does not contain the canonical SpecClaw plugin and stop.
The canonical locations are `$REPO_ROOT/plugins/specclaw/skills/` and
`$REPO_ROOT/plugins/specclaw/bin/`.

## Route a request

1. Choose the matching verb directory in
   `$SPECCLAW_PLUGIN_ROOT/skills/<verb>/SKILL.md`.
2. Read and follow that canonical `SKILL.md`; it is the source of truth for
   lifecycle requirements, artifacts, and approval gates.
3. When its instructions name a bare `specclaw-*` command, run the equivalent
   executable through `$SPECCLAW_PLUGIN_ROOT/bin/`.
4. When its instructions refer to `CLAUDE_PLUGIN_ROOT`, use
   `$SPECCLAW_PLUGIN_ROOT` as that resource root.
5. Keep `.specclaw/` state in the repository being operated on. Do not write
   lifecycle state into the adapter directory.

Available verbs are the directories currently present under
`$SPECCLAW_PLUGIN_ROOT/skills/`. If a requested verb has no matching canonical
directory, say so instead of inventing a workflow.

This is a repository-local skill. It is discovered when Codex is started in
this checkout (or a descendant); it does not install or configure a global
Codex skill.
