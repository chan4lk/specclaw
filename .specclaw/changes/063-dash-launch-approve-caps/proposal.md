# Proposal: specclaw-dash actions — launch fleet runs, approve lessons, edit context caps

**Created:** 2026-11-14
**Status:** ✅ Approved 2026-11-14
**Feature:** devloop
**Depends on:** 062-dash-pane, 061-review-recall-fix-proof, 065-core-context-gate-task-sizing

## Problem

The pane (062) only shows. To build a feature you still have to type fleet commands, approve proposed rules
in another skill, and edit caps in YAML. The goal is one place from which you start a feature and then leave.

## Proposed Solution

Pane actions. Each one runs an existing command; the pane owns no logic:
1. **Launch:** select approved changes or a `**Feature:**` module, then press Run. This runs
   `specclaw-fleet optin … --dry-run` and shows the plan. Confirm runs it for real, then
   `specclaw-fleet feature start <module>` or `trigger`. Fleet's consent rule holds: only items assigned to
   the user running the pane, tagged by that user.
2. **Approve lessons:** each rule proposed by `learn` has Approve and Reject buttons, which run
   `specclaw-review learn --apply <fp>` or record a rejection.
3. **Caps:** edit each role's context cap in `.specclaw/config.yaml` (`budget.roles.*.context`), within the
   range 065 defines. The pane writes config; the 065 hook enforces it, so caps still hold when the pane is closed.
4. **Dismissed suggestions:** list `plugins.dismissed` (059) with an undo.

## Scope

### In Scope
- The four actions in `specclaw-dash`, each with a confirm step for anything that spends a plan or pushes
- Tests on the action-to-command mapping

### Out of Scope
- Local (non-fleet) headless runs. That is `specclaw-extras:auto`; it can be added later.
- Any action that touches another person's work item or plan

## Impact

- **Size:** bounded — adds actions to the 062 pane over existing commands
- **Files affected:** ~6
- **Complexity:** medium
- **Size waiver:** about 450 counted lines. The required version bump adds 21 lines across 17 manifests, and two
  review rounds added the undo failure paths and an atomic launch guard. The code is one mapping module, one
  runner and the pane's actions; splitting it would ship buttons without their commands.
- **Risk:** high for Launch. It spends a plan and pushes a branch, so it always needs a dry-run first and an
  explicit confirm.

## Open Questions

- Can a mod pane trigger a command or a slash command directly? If not, Launch puts the exact command into the prompt for the user to send.

---

**To proceed:** Review this proposal and approve to begin planning.
