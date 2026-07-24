# Tasks: Git Worktrees Support

**Change:** git-worktrees
**Created:** 2026-03-28
**Total Tasks:** 3

## Summary

Add worktree-per-change git strategy to build.sh, update config template, update SKILL.md.

## Tasks

### Wave 1 — Core implementation

- [x] `T1` — Add worktree-per-change strategy to build.sh
  - Files: skill/scripts/build.sh
  - Estimate: medium
  - Notes: Modify all three subcommands. setup: when git.strategy is "worktree-per-change", create a worktree at .specclaw/worktrees/<change-name>/ on branch specclaw/<change-name>. If worktree already exists (resume), just verify it. Output the worktree path in config JSON as "worktree_path". Handle case where branch exists but worktree was removed. commit: when worktree strategy, run git add/commit inside the worktree directory (cd to worktree_path). The commit_prefix format stays the same. finalize: when worktree strategy, checkout main in main repo, merge the worktree branch (same as branch-per-change merge logic), then run `git worktree remove <path>` and delete the branch. If merge conflict, abort and keep worktree intact for manual resolution. Add a new subcommand `worktree-path <specclaw_dir> <change_name>` that just outputs the worktree directory path (for use by build-context.sh and agents).

### Wave 2 — Config and documentation

- [x] `T2` — Update config.yaml template with worktree-per-change option
  - Files: skill/templates/config.yaml
  - Depends: T1
  - Estimate: small
  - Notes: Update the git.strategy comment to include "worktree-per-change" as a third option. Add a comment explaining when to use it (parallel multi-change builds). Add git.worktree_dir setting (default: ".specclaw/worktrees") for the worktree base directory. Add .specclaw/worktrees/ to suggested .gitignore entries in a comment.

- [x] `T3` — Update SKILL.md and build-engine.md with worktree documentation
  - Files: skill/SKILL.md, skill/references/build-engine.md
  - Depends: T1
  - Estimate: small
  - Notes: In SKILL.md build section: add note that when worktree-per-change is configured, each change gets an isolated worktree. Agents spawned for tasks should receive the worktree path as their working directory (cwd parameter in sessions_spawn). In the setup step, mention the worktree_path from config JSON. In build-engine.md: add a section explaining the three git strategies, when to use each, and how worktrees enable parallel multi-change builds. Keep additions concise.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
