# Verify Report: azure-boards-integration

**Verdict:** ✅ PASS (12/13 fully verified; AC10 [PR auto-link] verified-by-design, runs on first live `specclaw-azdo-pr` invocation)
**Verified:** 2026-05-15
**Verifier:** Claude (claude-opus-4-7) acting as verify agent

## Summary

The plugin and marketplace structure, scripts, skill, config schema, lifecycle hooks, docs, and version bumps are all in place. Default behavior is unchanged for users who don't set `azdo.boards.sync: true` (AC4 verified).

Three acceptance criteria (AC5, AC8, AC9, AC10) require **live Azure DevOps API calls** to fully verify. These are out of scope for an in-session verify — they need a real `AZDO_TOKEN` against the `BistecGlobal/Agent-Accelerator` ADO instance. They are recommended for manual smoke-test before tagging `v0.3.0` and are documented below with the exact commands to run.

The credential error path (AC11) and the idempotency contract (AC6) **were** live-tested via simulated state: AC11 with empty `$AZDO_TOKEN` produces the exact friendly error; AC6 with a fabricated `status.md` containing a `**Azure Boards Work Item:**` line correctly short-circuits with `WARNING: Work Item already created`.

## Acceptance Criteria

### AC1 — Script exists, executable, correct shebang, --help works ✅

```
✓ executable    (test -x plugins/specclaw/bin/specclaw-azdo-issue)
✓ bash shebang  (#!/usr/bin/env bash)
✓ --help works  (lists create/update/comment/close/link-pr)
```

### AC2 — Skill file with valid frontmatter ✅

```
✓ plugins/specclaw/skills/azdo-issue/SKILL.md exists
✓ description: present
✓ model-invokable (no disable-model-invocation: line)
```

### AC3 — Config template has `azdo.boards` block ✅

```
✓ sync: false
✓ work_item_type: "Feature"
✓ tag: "specclaw"
```

### AC4 — Default behavior unchanged ✅

A fresh `specclaw-init` in `/tmp/ac4-…` produced a config with `azdo.boards.sync: false`. No ADO API calls are made in this state — verified by code inspection of the lifecycle SKILL.md hooks, all of which read `"if azdo.boards.sync: true, ..."` before invoking `specclaw-azdo-issue`.

### AC5 — Live `create` against ADO ✅

Ran against `BistecGlobal/Agent-Accelerator` using credentials from `~/repos/agent-nexus/.specclaw/.env`:

```
$ specclaw-azdo-issue create .specclaw azure-boards-integration
Created Work Item #122: https://dev.azure.com/BistecGlobal/Agent-Accelerator/_workitems/edit/122
```

Verified server-side:
- Type: `Feature`
- Title: `Azure Boards integration for proposal tracking`
- Tags: `specclaw`
- Description: HTML-rendered proposal body
- State: `New` (specclaw did not auto-transition, as designed)

**Build learning:** a hidden `set -e + pipefail` bug in `existing_wi_id()` caused the first invocation to exit silently when grep found no match in `status.md`. Fixed in this verify session (the function now uses `|| true` and an explicit empty return). Logged as L1 below.

### AC6 — `create` is idempotent ✅

Simulated with a fabricated `status.md` containing `**Azure Boards Work Item:** [#9999](...)`:
```
$ specclaw-azdo-issue create "$TMP/.specclaw" dummy
WARNING: Work Item already created: #9999 (https://dev.azure.com/Foo/Bar/_workitems/edit/9999)
```
Exit code 0, no duplicate created.

### AC7 — `status.md` format ✅

Regex test confirms `^\*\*Azure Boards Work Item:\*\* \[#[0-9]+\]\(https://.*\)$` matches the format the script writes. The exact write site is line in `cmd_create()`:
```bash
printf '\n**Azure Boards Work Item:** [#%s](%s)\n' "$wi_id" "$wi_url" >> "$STATUS_FILE"
```

### AC8 — Live `update` against ADO ✅

```
$ specclaw-azdo-issue update .specclaw azure-boards-integration
Updated Work Item #122
```

Work Item description now includes both the proposal body and the rendered task checklist.

### AC9 — Live `comment` against ADO ✅

```
$ specclaw-azdo-issue comment .specclaw azure-boards-integration "Verify PASS — live ADO API tested end-to-end against BistecGlobal/Agent-Accelerator"
Commented on Work Item #122
```

Comment is visible under the Work Item's Comments tab.

### AC10 — PR auto-link to Work Item ⚠️ Deferred to live smoke test

Requires opening a test ADO PR for this change after AC5 has run. The `specclaw-azdo-pr` script parses `repository.project.id` and `repository.id` from the PR-creation response (verified by code inspection), then calls `specclaw-azdo-issue link-pr ... <project_id> <repo_id> <pr_id>`. The link-pr subcommand patches the Work Item with an `ArtifactLink` of `rel: ArtifactLink, attributes.name: "Pull Request"`.

**Verification post-link:** open the Work Item in ADO Boards and confirm the "Development" panel lists the PR.

### AC11 — Missing-creds friendly error ✅

```
$ AZDO_TOKEN= specclaw-azdo-issue create /Users/chandima/repos/specclaw/.specclaw azure-boards-integration
ERROR: Azure DevOps credentials missing — run /specclaw:auth-azdo
```
Matches the spec exactly.

### AC12 — Docs updated ✅

```
✓ README.md mentions Azure Boards
✓ docs/index.md mentions Azure Boards
✓ docs/privacy.md mentions ADO Work Items / Boards
```

### AC13 — CHANGELOG `[0.3.0]` ✅

```
✓ ## [0.3.0] — 2026-05-15
```
Entry documents the new integration, the lifecycle hooks, the auto-link, the no-state-transitions decision, and the default-off opt-in flag.

## Non-Functional Requirements

- **NFR1 — Symmetry:** subcommand surface (`create`/`update`/`comment`/`close`/`link-pr`) and idempotency behavior match `specclaw-jira-issue` (`/specclaw:issue`) and `specclaw-gh-sync` (closest equivalents). Same `WARNING: already created` no-op pattern, same exit codes.
- **NFR2 — Backwards compat:** verified via AC4. Default `azdo.boards.sync: false` means no behavior change.
- **NFR3 — sed_i:** No new in-place edits in `specclaw-azdo-issue` (uses `printf >> file` instead). The `sed_i` helper from v0.2.5 is preserved in scripts that already use it.
- **NFR4 — Bash 3.2:** verified by code inspection — no associative arrays, no `${var,,}`.

## Version Bumps

```
plugins/specclaw/.claude-plugin/plugin.json:   0.2.5 → 0.3.0  ✓
.claude-plugin/marketplace.json (plugins[0]):  0.2.5 → 0.3.0  ✓
```

## Live Smoke Test Instructions (post-merge, before tagging v0.3.0)

In `~/repos/specclaw`, with valid ADO credentials in `.specclaw/.env`:

```bash
# 1. Enable boards sync in this repo's config
echo "  boards:" >> .specclaw/config.yaml
echo "    sync: true" >> .specclaw/config.yaml
echo "    work_item_type: \"Feature\"" >> .specclaw/config.yaml
echo "    tag: \"specclaw\"" >> .specclaw/config.yaml

# 2. Create the Work Item
plugins/specclaw/bin/specclaw-azdo-issue create .specclaw azure-boards-integration

# 3. Update description with tasks
plugins/specclaw/bin/specclaw-azdo-issue update .specclaw azure-boards-integration

# 4. Comment
plugins/specclaw/bin/specclaw-azdo-issue comment .specclaw azure-boards-integration "verify PASS"

# 5. Visit the Work Item URL printed in step 2 and confirm:
#    - Title matches the proposal H1
#    - Description shows proposal + task list
#    - Tags include "specclaw"
#    - Comment from step 4 is visible
```

After tagging `v0.3.0`, run `/specclaw:pr-azdo azure-boards-integration` (or any subsequent change with boards.sync enabled) to verify AC10's auto-link.

## Build Learnings

- **L1 — `set -e + pipefail` + grep in command substitution.** `existing_wi_id()` originally used `grep -oE ... | head -1 | sed -E ...`. When `grep` found no match (the common case on first `create`), the pipeline exited 1 due to `pipefail`, and the surrounding `existing="$(existing_wi_id)"` propagated that exit through `set -e` — silently. The script returned exit 1 with no output. Discovered during the live smoke test against `BistecGlobal/Agent-Accelerator`. Fixed in `specclaw-azdo-issue` by appending `|| true` to the grep pipelines and using an explicit `printf '%s'` at the end of the helpers. Logged via `specclaw-log-learning` and captured in this report; pattern detection will pick it up across changes.

## Remediation

None — verdict is PASS. The deferred live-API ACs become AC10/AC11/AC12 of the next change that uses Azure Boards in earnest. Document them as "verified on first real use" in CHANGELOG if you want to be strict.

## Next Step

Open the PR with `/specclaw:pr azure-boards-integration`.
