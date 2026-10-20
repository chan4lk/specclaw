---
description: Use when a planned change is ready to build, or the user says go or build it.
---

**Flow check:** run `specclaw-ensure-init .specclaw && specclaw-flow .specclaw`. If it prints `full`, read `$CLAUDE_PLUGIN_ROOT/references/full/build.md` and follow it instead of this file.

# specclaw build (lean)

1. `specclaw-validate-change .specclaw <change> build`, then `specclaw-build setup .specclaw <change>` (creates the branch). Commit `.specclaw/mock/index.html` and the change folder: `specclaw(<change>): mock + change`.
Before coding, read every file `specclaw-presets .specclaw` prints (project presets win over built-ins). Follow them in every file. If it exits non-zero, stop and show its errors.

2. For each pending task in `change.md`, in order:
   - Mark it in progress with `specclaw-update-task-status .specclaw/changes/<change>/change.md <T> in_progress`.
   - Write the minimum code that meets its ACs, following the presets and the project's existing patterns.
   - Tests: **at most one per AC**, written only for the ACs this task delivers. No speculative tests or abstractions.
   - Run the project's test command. On failure, fix and retry up to `loop.max_iterations` times (default 2). Then mark the task `failed` and stop with the error.
   - On success: `specclaw-update-task-status … <T> complete`, then `specclaw-build commit .specclaw <change> <T> "<title>" <files…>`.
3. **Refactor.** Run `specclaw-quality-scan .` and note `totals.duplicated_lines`; skip to step 4 if it is 0. Move each `duplicates[]` pair into the preset's **Shared** location (base class, generic handler, shared hook or utility). Re-scan and run the tests. Keep it only if duplicated lines dropped and the tests pass, then commit `specclaw(<change>): refactor`; otherwise discard it: `git restore` only the files the refactor edited, and delete only the files it created. Write `Quality: <before> → <after> duplicated lines` under `## Verify`. If a tool shows `not_run`, write that instead.
4. No review agents, no party panel, no learnings files. Do the work directly; spawn a subagent only for a large task that is independent of the others.
5. `specclaw-update-status .specclaw`. If `specclaw-gh-sync` is on PATH and `github.sync: true`, run `specclaw-gh-sync update .specclaw <change>`; skip silently otherwise. Say which screen now matches its mock section. Next step: `/specclaw:verify`.
