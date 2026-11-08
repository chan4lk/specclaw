# Spec: specclaw-fleet coordinated multi-change features

**Change:** 050-fleet-coordinated-features
**Created:** 2026-11-08
**Size:** architectural

## Functional Requirements

- **FR-1 Membership and dependencies live in git.**
  - A child change declares two lines in `proposal.md`, or in `change.md` for a lean change: `**Feature:** <module>` and, optionally, `**Depends on:** <change>, <change>`. The value can also be `none`.
  - `<module>` matches `^[a-z0-9][a-z0-9-]{0,40}$`.
  - A dependency on a change that isn't a member of the same feature is an error, and so is a cycle. Both are reported with the change names.
- **FR-2 Feature record.** `specclaw-fleet feature init <module>` writes `.specclaw/features/<module>/proposal.md` (title, the member list and waves), `status.md` and `state.json`, with the proposal approved by the caller.
  - It creates the feature's work item through `specclaw-azdo-issue create`. `specclaw-azdo-issue` resolves `<dir>/features/<name>` when `<dir>/changes/<name>` is missing, so a feature is a work-item-backed item like a change.
  - It refuses a module with no members.
  - The operator commits and pushes the record. The skill asks first.
- **FR-3 `specclaw-fleet feature plan <module>`.** Read-only:
  - the waves, in topological order;
  - each member's state: `not-opted-in`, `ready`, `waiting` (on <deps>), `running`, `pr_open`, `merged`, `failed`, or `conflict`;
  - the integration state.
  - `--json` gives machine output.
- **FR-4 Member state.**
  - A member is **merged** when its last fleet record has a `pr` whose AzDO pull request is `completed` into `feature/<module>`. This holds for any merge type, squash included.
  - **conflict:** an active PR whose `mergeStatus` is `conflicts`.
  - **failed:** the last record is `failed`, or the item is tagged `fleet:refused`.
  - **running:** dispatched with no PR yet.
  - **ready:** opted in, never dispatched, and every dependency merged.
  - **waiting:** opted in, never dispatched, and a dependency is not merged.
- **FR-5 `specclaw-fleet feature start <module>`.**
  - Requires the feature record on the pushed ref.
  - Creates `feature/<module>` on the remote from `fleet.ref` (default `main`) when it is missing. This is the only push fleet ever makes from the operator's machine, and the skill asks first.
  - Queues the pipeline on `feature/<module>`.
- **FR-6 `specclaw-fleet feature advance <module>`.** Idempotent. The pipeline runs it on every run of a `feature/*` branch.
  - Dispatches every `ready` member with `FLEET_REF=feature/<module>`, through the normal gates.
  - Leaves the dependents of a `failed` member waiting, and keeps going with everything else.
  - **Conflicts:** for a `conflict` member, it re-dispatches once with `--force` and `FLEET_MERGE_REF=feature/<module>`, then tags `fleet:conflict-retried`. A second conflict records `failed exit=merge-conflict` for a human.
  - **Integration:** once every member is `merged`, it dispatches the feature item in integration mode, once, guarded by the feature item's own `fleet:dispatched` claim.
- **FR-7 PR target.**
  - `specclaw-azdo-pr` honours `SPECCLAW_PR_TARGET` over `git.base_branch`.
  - The pod exports `SPECCLAW_PR_TARGET="${FLEET_PR_TARGET:-$FLEET_REF}"`, so a child dispatched from `feature/<module>` opens its PR into that branch. The draft PR uses the same target.
- **FR-8 Integration mode (`FLEET_MODE=integrate`).**
  - The pod clones `feature/<module>` and reads approval from `.specclaw/features/<module>/state.json`.
  - It works on the branch `specclaw/integrate-<module>`. The agent runs the project's tests and each member's verify, fixes integration breakage, and commits.
  - The pod then pushes the branch and opens the PR `specclaw/integrate-<module> → fleet.ref`: a draft when the agent reports a failure, with the feature work item linked.
- **FR-9 Merge base.** When `FLEET_MERGE_REF` is set, the pod merges `origin/$FLEET_MERGE_REF` into the resumed change branch before the agent runs. On conflict, it leaves the markers in place, and the prompt tells the agent to resolve them first.
- **FR-10 Pipelines.**
  - Both templates trigger on `main` and `feature/*`.
  - On a `feature/<module>` run, the dispatch step runs `specclaw-fleet feature advance <module>` instead of the main-branch scan.
- **FR-11 Skill.** `/specclaw-fleet:feature` drives the flow:
  1. `feature plan`;
  2. `feature init` (with confirmation);
  3. `optin` for every member and the feature item (one confirmation);
  4. commit and push the record (with confirmation);
  5. `feature start`;
  6. `status --watch`, until the integration PR exists or a member fails.

## Non-Functional Requirements

- NFR-1: fleet files are 80 lines or fewer, have no comments, and are ShellCheck clean.
- NFR-2: tests are offline and table-driven, with one per AC. Wave computation and cycle detection are pure functions.
- NFR-3: `feature plan` never writes. `feature advance` writes only through `dispatch` (gates unchanged) and the tags named above.

## Acceptance Criteria

- **AC-1 Membership and waves:** `Feature` and `Depends on` parse from `proposal.md` and from a lean `change.md`. The waves come out in topological order. An unknown dependency, a cycle and a bad module name are each refused with names. Covers FR-1 and FR-3.
- **AC-2 Feature record:** `feature init` writes the record, creates the work item through the features fallback, and refuses an empty module. Covers FR-2.
- **AC-3 Member states:** the table maps records, PR status and tags to `merged`, `conflict`, `failed`, `running`, `ready`, `waiting` and `not-opted-in`, and a squash-merged PR counts as merged. Covers FR-4.
- **AC-4 advance:** it dispatches only ready members with `FLEET_REF=feature/<m>`, and the dependents of a failed member wait while the rest proceed. It retries a conflict once, then marks it failed. It dispatches integration exactly once, when every member is merged. Re-running it is a no-op. Covers FR-6.
- **AC-5 PR target and integration pod:** `specclaw-azdo-pr` targets `SPECCLAW_PR_TARGET`. A child pod's PR goes into the feature branch. The integration pod reads feature approval, uses `specclaw/integrate-<m>` and opens its PR into `fleet.ref`. `FLEET_MERGE_REF` merges before the agent runs. Covers FR-7, FR-8 and FR-9.
- **AC-6 Pipelines, start and skill:** the templates trigger on `feature/*` and run advance there. `feature start` creates the branch only when it is missing, then queues the pipeline. The skill exists, and every suite runs in CI. Covers FR-5, FR-10 and FR-11.

## Edge Cases

- A member that is merged by hand outside fleet has no fleet PR record. It counts as merged when its change branch is an ancestor of `feature/<m>` (the fallback check).
- A feature whose only member fails: integration never dispatches, and `plan` shows `blocked by <member>`.
- A member removed from the feature after `init`: `plan` warns that the record's member list differs from the members found now. The live scan wins.
