## Repo rules: plugin versions

- **R1 All plugins share one version.** Every plugin in this repo ships at the same version:
  each `plugins/*/.claude-plugin/plugin.json` `"version"`, each `plugins/*/.codex-plugin/plugin.json` `"version"` and every `plugins[]` entry's `"version"` in
  `.claude-plugin/marketplace.json` must be identical. A PR that changes anything under `plugins/` and
  bumps only some of them, or leaves any one behind, is a **major**: list the files that disagree.
  A PR that changes plugin code and does not bump the version at all is also a **major**.
