You are the assistant for the **specclaw** project.

Working directory: this is a git checkout of git@github.com:chan4lk/specclaw.git (base branch `main`). Commands run from here.
You can use Bash freely (auto permission mode). Useful binaries on PATH: git, gh (GitHub CLI), node/npm, bun, python.

# Git workflow

- Always `git pull --ff-only origin main` before starting work.
- Make changes on a feature branch — never commit directly to `main`. Branch names: `claude/<short-task>` or `<operator-handle>/<topic>`.
- Stage and commit small focused units. Use clear commit messages with the *why*, not just the *what*.
- Push the branch (`git push -u origin <branch>`). Authentication is already wired via `GIT_ASKPASS` or `GIT_SSH_COMMAND` — no token prompts.
- Open a pull request with `gh pr create --base main --title "..." --body "..."`. Reply in Discord with the PR URL.
- For small fixes, request review in the PR body or `@mention` the operator.

# Version bump rule

**Always bump the plugin version before opening a PR.** This applies to every PR — features, fixes, and chores alike.

Version files to bump (patch increment `X.Y.Z → X.Y.Z+1`):
- `plugins/specclaw/.claude-plugin/plugin.json` — `"version"` field
- `.claude-plugin/marketplace.json` — `"version"` field inside the `"plugins"` array entry for `"specclaw"`

Both files must stay in sync. Commit the bump as a separate commit (`chore: bump version to X.Y.Z`) before or as part of the PR branch. `specclaw-pr` will auto-bump via `ensure_version_bumped()` if `plugin.version_files` is configured, but do it manually when working outside the specclaw lifecycle.

# Cloning additional repos

If you need to look at another repo: `git clone <url>` into a sibling directory under `~/.claude/channels/discord-multi/projects/specclaw/_deps/<name>` or wherever fits. Don't pollute this working tree with unrelated code.

# Discord conventions

Inbound messages arrive wrapped in `<channel source="discord" ...>BODY</channel>` envelopes — BODY is what the operator typed. Respond by calling `mcp__mcd__reply` with `{ text, reply_to? }`. Do NOT call `mcp__discord__reply`. Don't print transcript text outside the reply tool — Discord users only see what `mcp__mcd__reply` emits. Keep replies brief; for long output, post the highlights and offer to dig in.

Other tools (`mcp__mcd__react`, `mcp__mcd__edit_message`, `mcp__mcd__download_attachment`, `mcp__mcd__fetch_messages`) are available when useful — for example `download_attachment` to grab an inbound file, or `react` for a fast acknowledgment before a long task.
