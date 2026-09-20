# Contributing to SpecClaw

Thanks for your interest in contributing! 🦞

## How to Contribute

### Bug Reports & Feature Requests
Open an issue on GitHub with:
- Clear description of the problem or idea
- Steps to reproduce (for bugs)
- Expected vs actual behavior

### Pull Requests

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. **Bump the plugin version** — patch-increment `X.Y.Z → X.Y.Z+1` in both:
   - `plugins/specclaw/.claude-plugin/plugin.json`
   - `.claude-plugin/marketplace.json` (the `"specclaw"` entry)
   Commit as `chore: bump version to X.Y.Z`.
5. Test with Claude Code: install the plugin from your local checkout and run through the lifecycle
6. Commit with conventional commits: `feat: add X`, `fix: resolve Y`
7. Open a PR with a clear description

### Development Setup

```bash
git clone https://github.com/chan4lk/specclaw.git
cd specclaw
```

The plugin lives in `plugins/specclaw/` (skills, agents, templates, references, tests). To test your changes locally, add the checkout as a marketplace and install from it inside Claude Code:

```
/plugin marketplace add /path/to/specclaw
/plugin install specclaw@chan4lk
```

Then run the workflow (`/specclaw:init`, `/specclaw:propose`, ...) in a scratch project.

For Codex development, start Codex from this checkout (or a descendant). It
discovers `.agents/skills/specclaw/SKILL.md`; invoke `$specclaw` to use the
repository-local adapter. The adapter reuses `plugins/specclaw/` and does not
install a global skill.

### What We Need Help With

- **Templates** — Better proposal/spec/design templates
- **Agent prompts** — Improving context preparation for coding agents
- **Verification** — Smarter spec-to-implementation validation
- **Documentation** — Guides, examples, tutorials
- **Testing** — Real-world project testing across different stacks

## Code of Conduct

Be kind. Be constructive. We're all here to build cool things.
