---
description: Use when a project has no .specclaw/ directory and the user wants to start using specclaw.
---

# specclaw init

1. Ask for a project name and one-line description if not given, then run `specclaw-init . "<name>" "<description>"`. It writes `flow: lean`, lean defaults and `.specclaw/mock/index.html`. It refuses if `.specclaw/` exists; never overwrite.
2. Init prints the presets it detected from the manifests (`presets:` in `config.yaml`). Ask the user to confirm or change them; the choices are `python`, `nextjs`, `node`, `dotnet` and `react-spa`, plus any project preset in `.specclaw/presets/<name>.md`, and `base` always applies. Write the answer to `presets: [..]`. Custom presets go in `.specclaw/presets/` (format in its `README.md`).
3. If the user wants the full flow (proposal, spec, design, tasks), follow `$CLAUDE_PLUGIN_ROOT/references/full/init.md` instead of steps 1–2.
4. Suggest tracking `.specclaw/` in git.
5. Next step: `/specclaw:propose`. Change 001 draws the minimal mock of the whole app.
