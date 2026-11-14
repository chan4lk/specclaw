# Proposal: Project-local custom presets

**Created:** 2026-10-19
**Status:** 🟡 Draft

## Problem

Coding presets (`base`, `dotnet`, `node`, `nextjs`, `python`, `react-spa`) live only in the plugin's
`plugins/specclaw/presets/`. A client team that wants its own house rules ("our .NET flavour", a
`go` preset, a company-wide base) must fork or PR the specclaw repo. specclaw-review already solves
the same shape for review rules with `.specclaw/review/rules/*.md` in the client repo; presets have
no equivalent.

## Proposed Solution

Let a project keep presets in `.specclaw/presets/<name>.md`, committed in the client repo.

- **Resolution.** For each name in `config.yaml` `presets: [..]` (and the implicit `base`):
  `.specclaw/presets/<name>.md` if it exists, else `$CLAUDE_PLUGIN_ROOT/presets/<name>.md`.
  A local file with a built-in's name **replaces** it; a new name (e.g. `acme-dotnet`, `go`) adds one.
  An unknown name (in neither place) is reported, not silently skipped.
- **One resolver.** New `specclaw-presets .specclaw` bin prints the resolved file paths, one per line,
  `base` first, and warns on unknown names. Build skill(s) read whatever it prints instead of
  hard-coding `$CLAUDE_PLUGIN_ROOT/presets/`.
- **Extend, not only replace.** A local preset may start with `Extends: dotnet` — the resolver then
  emits the built-in first, then the local file, so a team can add rules without copying the built-in.
- **Init.** `specclaw-init` lists local presets (if any) alongside built-ins when asking the user to
  confirm `presets:`; creates `.specclaw/presets/README.md` explaining the format (mirrors
  specclaw-review's lazy rules README).
- **Mechanical checks.** `specclaw-preset-check` keeps its existing built-in rules (max_lines,
  comment, dotnet layer). Custom presets are prose guidance read by build; they add no new mechanical
  checks in this change.

## Scope

### In Scope
- `.specclaw/presets/<name>.md` lookup with local-over-built-in precedence and `Extends:` support.
- `specclaw-presets` resolver bin + tests.
- Lean build SKILL and full build reference read presets via the resolver.
- `init` skill / `specclaw-init`: surface local presets; scaffold `presets/README.md`.
- Docs: preset format section (README or `presets/README.md`).

### Out of Scope
- User-global presets (`~/.specclaw/presets/`) or fetching presets from a remote URL/package.
- Custom mechanical rules for `specclaw-preset-check` declared in preset files.
- Auto-detection for custom presets (detect rules stay in `specclaw-init` for built-ins).
- A `/specclaw:preset` authoring skill.

## Impact

- **Size:** bounded (alters the existing preset-reading flow in build/init; new bin is a small resolver)
- **Files affected:** ~7 (new `bin/specclaw-presets`, its test, `skills/build/SKILL.md`, full build reference, `skills/init/SKILL.md`, `bin/specclaw-init`, docs) + version bump
- **Complexity:** small
- **Risk:** low — no local presets means today's behaviour exactly

## Open Questions

Resolved at approval (operator: "go with your defaults"):
- Same-name local file **replaces** the built-in; `Extends: <name>` is the explicit extend path.
- `base` follows the same rule — a local `base.md` replaces it; `Extends: base` keeps it.
- Directory is fixed at `.specclaw/presets/`; no `presets_dir` config key.

---

**To proceed:** Review this proposal and approve to begin planning.
