---
description: Interactively co-author spec.md for an approved proposal via the spec-author subagent. The agent walks the user through the spec template section by section, applying named brainstorming techniques (5 Whys, Jobs-to-be-Done, Inversion, Pre-mortem, MoSCoW) and challenging vague requirements. Use when you want a high-quality, dialogue-driven spec instead of the single-shot one /specclaw:plan produces by default. Standalone alternative to /specclaw:plan --author-spec.
---

# specclaw author-spec

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Interactively author `spec.md` for an approved proposal.

1. **Validate:** run `specclaw-validate-change .specclaw <change> plan`. If it fails (typically: `proposal.md` missing), report the missing prerequisite and stop.
2. **Check for existing spec:** if `.specclaw/changes/<change>/spec.md` already exists, show the user the first few lines and ask whether to overwrite. Default is **no** — abort if the user does not explicitly confirm overwrite.
3. **Invoke the agent:** call the `spec-author` subagent via the `Agent` tool with `subagent_type: "spec-author"` and a prompt instructing it to author the spec for `<change>`. The agent reads `proposal.md` and writes `spec.md` itself; do not wrap the dialogue in this skill.
4. **Update status:** `specclaw-update-status .specclaw`.
5. **GitHub sync** (if `github.sync: true` in `config.yaml`): `specclaw-gh-sync update .specclaw <change>` to refresh the issue with the new spec.
6. **Azure Boards sync** (if `azdo.boards.sync: true`): `specclaw-azdo-issue update .specclaw <change>`.

Do not proceed to `/specclaw:plan` automatically. After `spec.md` is written, the user can run `/specclaw:plan <change>` (which will use the freshly-authored `spec.md` and generate `design.md` + `tasks.md`) when ready.
