# specclaw plan

**Optional plugins:** `specclaw-gh-sync`, `specclaw-azdo-*` and `specclaw-jira-issue` come from specclaw-sync, and `specclaw-party` from specclaw-extras. Skip any step whose command is not on PATH (`command -v`).

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

**Timing (change 028).** Open a phase span when you start and close it when the artifact is written — `specclaw-timer start .specclaw <change> plan --kind phase --label plan || true`, then `specclaw-timer stop .specclaw <change> plan || true`. Cheap, and it finally answers how long this phase costs us. Both calls end in `|| true`: a stopwatch is never a reason to stop.

Turn an approved proposal into an executable plan.

## Flags

- `--author-spec` — delegate spec authoring to the `spec-author` subagent for an interactive, technique-driven dialogue (5 Whys, Jobs-to-be-Done, Inversion, Pre-mortem, MoSCoW). When this flag is present, **pause for explicit user approval of `spec.md`** before generating `design.md` and `tasks.md`. Without the flag, behavior is unchanged (single-shot generation, no dialogue) so `/specclaw-extras:auto` remains non-interactive.

  Detect the flag as a whitespace-delimited token anywhere in ARGUMENTS (positional-agnostic), and strip it before using the rest of ARGUMENTS as `<change>`.

1. **Validate:** run `specclaw-validate-change .specclaw <change> plan`. If it fails, report missing prerequisites and stop.

   **Acquire the concurrency lock (change 038):** `specclaw-change-lock .specclaw acquire <change> --phase plan`. If it refuses (a live or unexpired-stale lock from another plan/build/verify/pr dispatch on this change), report its stderr message and stop — do not proceed to step 2. `plan` has no dedicated binary, so this call lives here rather than inside a `bin/` script, the same way `specclaw-validate-change` is invoked directly from this step. The lock is released at step 10, below — including after the `--author-spec` approval pause, not before it, since that pause is still part of this same dispatch.
2. Read `.specclaw/changes/<change>/proposal.md`.
3. Analyze the existing codebase (file structure, patterns, dependencies relevant to the change). **Also read `.specclaw/context.md` if it exists** — it contains project-level coding rules, patterns, architecture decisions, and constraints; apply them throughout spec, design, and tasks generation.
   - **Codebase survey:** build a structured survey and keep it in your working context for spec/design/tasks generation: top-two-level directory summary (e.g. from `git ls-files | cut -d/ -f1-2 | sort -u`), detected manifests (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `*.csproj`, `pom.xml`, `Makefile`, ...) and the languages/tooling they imply, and where tests live.
   - **Discovered project docs:** run `specclaw-discover-context .specclaw list` to see ranked candidate docs (rank, line count, path), then `specclaw-discover-context .specclaw emit` for the budget-capped digest. Read the digest and apply the project's documented conventions, constraints, and non-goals throughout planning. Prefer docs most relevant to this change when deciding what to read in depth. **Cite your evidence:** when a spec requirement, design decision, or task constraint comes from a discovered doc, name the doc path and quote the exact line(s) it rests on — never attribute a claim to a doc without a quote. If discovery is disabled or finds nothing, both commands print nothing — skip this step silently.
   - **Promoted spec knowledge:** read `.specclaw/knowledge/spec-guidelines.md` if it exists — it holds spec/design guidance promoted from earlier build learnings; apply it when writing `spec.md` and `design.md`.
3b. If `proposal.md` has a `## Dependency Bypass`, `## Item Split` or `## Resumes Split` section, the specclaw-bf plugin's `references/carry-through.md` (Plan) applies here.

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
     - **If `spec.md` already exists** (e.g. authored previously via `/specclaw-extras:author-spec`): do not overwrite it; skip the spec step and proceed to `design.md` / `tasks.md`.
   - `design.md` — technical approach, architecture, file changes map, key decisions, risks. Template: `$CLAUDE_PLUGIN_ROOT/templates/design.md`. **When discovery produced docs, add a "Grounding sources" section** listing the discovered files you actually used — each entry cites the path plus the specific convention or quoted line applied. The paper trail for what informed the design, backed by quotable evidence rather than vague attribution.
   - `tasks.md` — ordered tasks grouped into waves with dependencies. Template: `$CLAUDE_PLUGIN_ROOT/templates/tasks.md`. **Tag each task with an optional `Kind:` hint** (`frontend | backend | docs | test | config | refactor | impl | migration`) inferred from what the task does — it lets `build.dynamic_agents` (when enabled) synthesize a specialized subagent with the right role, minimal tools, and cost-appropriate model. When a task's nature is genuinely mixed or unclear, omit `Kind` and build will classify heuristically (default `impl`).
4b. **Size each task by context (change 065).** A single-job agent peaks far below one that bundles
   several, and quality falls long before the window is full. Run
   `specclaw-budget estimate .specclaw <change>`: it prints `<id> read=<n> context=<n>` per task with
   `Files:` (read = 26000 tokens of start-up plus the files at 2.2 characters a token). Add the
   diff the task will type (about 60 tokens a line) and write the total as `- Context: <n>` under
   the task. Split any task over 60000 by module or file group, never into a test task and a code
   task, and re-run until it exits 0. Tag UI tasks `Kind: frontend` and server tasks
   `Kind: backend`: the kind picks the build agent, and so its model (`budget.routing`).
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
