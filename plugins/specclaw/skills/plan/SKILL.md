---
description: Generate spec, design, and ordered task list for an approved proposal. Reads proposal.md, analyzes the codebase, then writes spec.md, design.md, and tasks.md. Run after /specclaw:propose has been approved, before /specclaw:build.
---

# specclaw plan

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

**Timing (change 028).** Open a phase span when you start and close it when the artifact is written — `specclaw-timer start .specclaw <change> plan --kind phase --label plan || true`, then `specclaw-timer stop .specclaw <change> plan || true`. Cheap, and it finally answers how long this phase costs us. Both calls end in `|| true`: a stopwatch is never a reason to stop.

Turn an approved proposal into an executable plan.

## Flags

- `--author-spec` — delegate spec authoring to the `spec-author` subagent for an interactive, technique-driven dialogue (5 Whys, Jobs-to-be-Done, Inversion, Pre-mortem, MoSCoW). When this flag is present, **pause for explicit user approval of `spec.md`** before generating `design.md` and `tasks.md`. Without the flag, behavior is unchanged (single-shot generation, no dialogue) so `/specclaw:auto` remains non-interactive.

  Detect the flag as a whitespace-delimited token anywhere in ARGUMENTS (positional-agnostic), and strip it before using the rest of ARGUMENTS as `<change>`.

1. **Validate:** run `specclaw-validate-change .specclaw <change> plan`. If it fails, report missing prerequisites and stop.

   **Acquire the concurrency lock (change 038):** `specclaw-change-lock .specclaw acquire <change> --phase plan`. If it refuses (a live or unexpired-stale lock from another plan/build/verify/pr dispatch on this change), report its stderr message and stop — do not proceed to step 2. `plan` has no dedicated binary, so this call lives here rather than inside a `bin/` script, the same way `specclaw-validate-change` is invoked directly from this step. The lock is released at step 10, below — including after the `--author-spec` approval pause, not before it, since that pause is still part of this same dispatch.
2. Read `.specclaw/changes/<change>/proposal.md`.
3. Analyze the existing codebase (file structure, patterns, dependencies relevant to the change). **Also read `.specclaw/context.md` if it exists** — it contains project-level coding rules, patterns, architecture decisions, and constraints; apply them throughout spec, design, and tasks generation.
   - **Codebase survey:** build a structured survey and keep it in your working context for spec/design/tasks generation: top-two-level directory summary (e.g. from `git ls-files | cut -d/ -f1-2 | sort -u`), detected manifests (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `*.csproj`, `pom.xml`, `Makefile`, ...) and the languages/tooling they imply, and where tests live.
   - **Discovered project docs:** run `specclaw-discover-context .specclaw list` to see ranked candidate docs (rank, line count, path), then `specclaw-discover-context .specclaw emit` for the budget-capped digest. Read the digest and apply the project's documented conventions, constraints, and non-goals throughout planning. Prefer docs most relevant to this change when deciding what to read in depth. **Cite your evidence:** when a spec requirement, design decision, or task constraint comes from a discovered doc, name the doc path and quote the exact line(s) it rests on — never attribute a claim to a doc without a quote. If discovery is disabled or finds nothing, both commands print nothing — skip this step silently.
   - **Promoted spec knowledge:** read `.specclaw/knowledge/spec-guidelines.md` if it exists — it holds spec/design guidance promoted from earlier build learnings; apply it when writing `spec.md` and `design.md`.
3b. **Dependency bypass carry-through.** If `proposal.md` has a `## Dependency Bypass` section, read `.specclaw/analysis/module-stubs.md` for each cited `ST-###` and read `$CLAUDE_PLUGIN_ROOT/references/stub-discipline.md`. The spec is where a bypass stops being a scheduling decision and becomes build obligations — carry it forward explicitly in all three files:

- **`spec.md` → `## Bypassed Dependencies`:** one subsection per `ST-###` (substitutes / strategy / stands in with / scoping mechanism / which criteria it backs / when it retires).
- **`spec.md` → `## Acceptance Criteria`:** label **every** criterion `[real]` or `[stub: ST-###]`. No criterion goes unlabelled on a change with a bypass — an unlabelled criterion reads as verified against real behaviour, and that is exactly the false impression the labels exist to prevent.
- **`spec.md` → two mandatory criteria per stub:** (1) the dev/test-scoping assertion, **naming the repo's own isolation mechanism** so a reviewer can check it — "the stub is dev-only" restates the rule instead of testing it; (2) the registry-completion obligation (`Fakes` and `Implementation` carry a real `file:line`).
- **`design.md`:** how the stub is built in *this* repo's stack and what makes it structurally unreachable from production.
- **`tasks.md`:** an explicit stub-implementation task (`Kind: impl`) that the consuming tasks depend on, in an earlier wave.

If the spec cannot state a checkable scoping mechanism — because the repo has no existing way to keep code out of production — **say so and stop before writing tasks**. That is a finding to hand back, not a gap to plan around: a stub with no isolation mechanism is a fabricated response shipped to production.

Skip all of this when the proposal has no bypass section, which is the normal case.

3c. **Item-split carry-through.** If `proposal.md` has a `## Item Split` or `## Resumes Split` section, read the cited `IS-###` in `.specclaw/analysis/item-splits.md` and read `$CLAUDE_PLUGIN_ROOT/references/split-discipline.md`. **A split is not a bypass** — nothing is faked, so no criterion is labelled `[stub: ...]` because of it and there is no scoping mechanism to assert. What the spec owes a split is **scope honesty**:

**Now-slice (`## Item Split`):**

- **`spec.md` → `## Item Split`:** the `IS-###`, what this change implements, what is deferred, the `DR-###` rules each half covers, what unblocks the remainder, and **where the deferred scope will attach** — that seam is part of this change's design even though its implementation is not.
- **`spec.md` → `## Acceptance Criteria`:** criteria cover the **now-slice only**. Any criterion for deferred scope is absent or explicitly out of scope citing the `IS-###`. A spec that states criteria for scope this change is not building produces a verify run that fails for the right reason and a reviewer who cannot tell why.
- **One mandatory criterion:** the deferred scope is genuinely **absent, not half-present**. A partly-wired deferred layer is worse than an absent one, because it looks built.
- **`tasks.md`:** no task for deferred scope. **If a task cannot be completed without it, the partition is wrong — say so and stop.** That is a decision to hand back, not one to adjust by quietly moving the boundary.

**Resume (`## Resumes Split`):**

- **`spec.md` → `## Resumed From Split`:** the `IS-###`, what the earlier slice built, and its change/PR/replay evidence.
- **Label every criterion the earlier slice already satisfied `[already built: IS-###]` and mark it out of scope.** They stay visible so the item's full acceptance basis reads in one place; this change is not measured against them.
- **`tasks.md`:** the deferred scope plus its integration, and nothing else. Re-specifying completed scope turns a resume into a rewrite of working code — precisely what the `IS-###` record exists to prevent.

Skip all of this when the proposal has neither section, which is the normal case.

3d. **Teaching gate** (if `teach.enabled: true`, via `specclaw-teach .specclaw status`): surface each significant design decision as scored options and **let the user choose before step 4a writes `design.md` (architectural) or the `## Approach` section (bounded); skip for a spike**. Deciding silently and documenting afterwards defeats the mode. See the Teaching mode section at the end of this skill.

4. **Read the change's size first** — `specclaw-validate-change .specclaw <change> status` prints
   `Size: <spike|bounded|architectural>`. It decides what this step writes:

   | Size | Write | Then |
   |---|---|---|
   | **spike** | `findings.md` only, from `$CLAUDE_PLUGIN_ROOT/templates/findings.md` | **release the concurrency lock first** (`specclaw-change-lock .specclaw release <change> \|\| true` — `archive/SKILL.md` has no lock handling of its own, so a spike that skips straight there without this step leaves step 1's lock held until it goes stale), then present the findings, get an explicit *noted*, and go straight to `/specclaw:archive`. `build`, `verify` and `pr` are refused for a spike — say so rather than attempting them. |
   | **bounded** | `spec.md` and `tasks.md` | `spec.md` carries an `## Approach` section, **≤ 10 lines**, holding the one design decision and the file map. That map is what `verify` checks scope against, so it is not optional. **Do not write `design.md`.** |
   | **architectural** | `spec.md`, `design.md`, `tasks.md` | exactly as below. |

   A change with no recorded size is `architectural`. When in doubt, ask rather than assume — an
   under-sized change loses its design record, and the ratchet only goes the other way.

4a. Generate the files in `.specclaw/changes/<change>/` (the full set shown here is the
   architectural one; drop `design.md` for bounded, and write only `findings.md` for a spike):
   - `spec.md` — functional requirements, non-functional requirements, acceptance criteria, edge cases.
     - **If `--author-spec` is set:** invoke the `spec-author` subagent via the `Agent` tool with `subagent_type: "spec-author"` to author the spec interactively. After the agent writes the file, **STOP and require explicit user approval** (e.g. "approved", "yes", "go") before proceeding to `design.md` and `tasks.md`. Do not generate the remaining files until the user approves.
     - **Otherwise:** generate `spec.md` directly using `$CLAUDE_PLUGIN_ROOT/templates/spec.md` as a starting template (single-shot, no dialogue).
     - **If `spec.md` already exists** (e.g. authored previously via `/specclaw:author-spec`): do not overwrite it; skip the spec step and proceed to `design.md` / `tasks.md`.
   - `design.md` — technical approach, architecture, file changes map, key decisions, risks. Template: `$CLAUDE_PLUGIN_ROOT/templates/design.md`. **When discovery produced docs, add a "Grounding sources" section** listing the discovered files you actually used — each entry cites the path plus the specific convention or quoted line applied. The paper trail for what informed the design, backed by quotable evidence rather than vague attribution.
   - `tasks.md` — ordered tasks grouped into waves with dependencies. Template: `$CLAUDE_PLUGIN_ROOT/templates/tasks.md`. **Tag each task with an optional `Kind:` hint** (`docs | test | config | refactor | impl | migration`) inferred from what the task does — it lets `build.dynamic_agents` (when enabled) synthesize a specialized subagent with the right role, minimal tools, and cost-appropriate model. When a task's nature is genuinely mixed or unclear, omit `Kind` and build will classify heuristically (default `impl`).
5. Record each phase as its file lands — one call per artifact, immediately after writing it:
   ```bash
   specclaw-set-phase .specclaw <change> spec done
   specclaw-set-phase .specclaw <change> design done      # architectural only
   specclaw-set-phase .specclaw <change> tasks done
   ```
   A bounded change skips the `design` call because it has no `design.md`; a spike records none of
   the three.
   `specclaw-set-phase` is the only writer of phase state — it records `state.json` and upserts the matching row in `status.md`. Never hand-edit those rows. With `--author-spec`, run the `spec` call before pausing for approval, and the other two after.
6. Present a plan summary to the user (counts of FRs, ACs, tasks, waves).
7. Update status: `specclaw-update-status .specclaw`.
8. **GitHub sync** (if enabled): `specclaw-gh-sync update .specclaw <change>` to attach the task checklist to the GitHub Issue.
9. **Azure Boards sync** (if `azdo.boards.sync: true`): `specclaw-azdo-issue update .specclaw <change>` to refresh the Work Item description with the rendered task checklist.
10. **Jira sync** (if `jira.enabled: true`): `specclaw-jira-issue update .specclaw <change>` to refresh the issue description with the rendered task checklist, then `specclaw-jira-issue transition .specclaw <change> plan` to move the card out of the backlog. The transition warns and continues when the project workflow has no matching status.
11. **Release the concurrency lock:** `specclaw-change-lock .specclaw release <change> || true` — always, on every path that reaches this point (single-shot or `--author-spec`), and best-effort: a release failure must never be reported as a plan failure.

## Planner guardrails

When generating `tasks.md`, apply the same rules `/specclaw:build` injects into coding agents — see `references/agent-guardrails.md`. In particular: **Rule 1 (Think Before Coding)** — state assumptions explicitly in the spec/design and ask if anything is unclear, rather than picking silently between interpretations. **Rule 2 (Simplicity First)** — no speculative tasks, no over-decomposition; if three tasks could be one, make it one.

## Teaching mode (if `teach.enabled: true`)

Check with `specclaw-teach .specclaw status`. When enabled, design decisions become the user's, not yours:

1. For each significant decision in `design.md`, present **2–4 options** in a table with pros, cons, learning cost and run cost — including at least one option *simpler* than your recommendation. Naming and rejecting the simpler option with a reason is itself the lesson.
2. Give **one recommendation with the single deciding factor** — not a list — plus **what would change your mind**. Then stop and let the user choose.
3. Record their choice and their reason **verbatim** in `design.md` under Key Decisions, and log it: `specclaw-teach .specclaw <change> log decision "<what and why>"`. If they choose against your recommendation, their reason is the rationale, not yours.

Full option-table format and worked example: `references/teaching-mode.md`.
