# Spec: Project-local custom presets

**Change:** 045-project-custom-presets
**Size:** bounded

## Functional Requirements

- **FR-1** A project may keep presets in `.specclaw/presets/<name>.md`.
- **FR-2** `specclaw-presets <specclaw-dir>` prints, one absolute path per line, the preset files build must read: `base` first, then each name in `config.yaml` `presets: [..]` in order, no duplicates.
- **FR-3** For each name, `<specclaw-dir>/presets/<name>.md` wins over `$PLUGIN/presets/<name>.md`. `base` follows the same rule.
- **FR-4** A local preset that opens with frontmatter `---` / `extends: <name>` / `---` emits the resolved `<name>` file (built-in when the local file *is* `<name>.md`) before itself. One level only; `extends` naming an unknown preset is an unknown name (FR-5). `extends` is read only from frontmatter (operator decision after review round 3 escalated on line-based detection); any other frontmatter key or an unclosed block is an error.
- **FR-5** A name found in neither place prints `specclaw-presets: unknown preset '<name>'` on stderr, is skipped, and the command exits 1 after printing the rest.
- **FR-6** Lean build reads the files `specclaw-presets .specclaw` prints instead of hard-coded `$CLAUDE_PLUGIN_ROOT/presets/`.
- **FR-7** `specclaw-init` creates `.specclaw/presets/README.md` describing the format; the init skill lists local presets as choices alongside built-ins.

## Non-Functional

- No `.specclaw/presets/` dir → output is exactly today's set (built-in base + configured built-ins).
- Names are restricted to `[a-z0-9-]+`; anything else is an unknown name (no path traversal out of the presets dirs).

## Acceptance Criteria

- **AC-1** No local dir, `presets: [dotnet]` → prints built-in `base.md` then built-in `dotnet.md`, exit 0.
- **AC-2** Local `dotnet.md` without `Extends:` → prints built-in `base.md`, local `dotnet.md` only.
- **AC-3** Local `dotnet.md` with frontmatter `extends: dotnet` → prints built-in `dotnet.md` then local `dotnet.md`.
- **AC-4** `presets: [acme]` with local `acme.md` → printed; `presets: [nope]` → stderr warning, exit 1, `base` still printed.
- **AC-5** Name `../x` → treated as unknown, exit 1.
- **AC-6** `specclaw-init` on a fresh dir creates `.specclaw/presets/README.md`.
- **AC-7** Lean build SKILL.md references `specclaw-presets` and no longer hard-codes `presets/base.md`.

## Edge Cases

- `presets: []` → `base` only.
- A local `base.md` replaces built-in base unless its frontmatter says `extends: base`.

## Approach

One resolver bin owns lookup; build and init only call or describe it. Precedence is local-over-built-in
per name, with frontmatter `extends:` as the explicit additive path. Full flow build does not read presets today, so
it stays untouched.

File map:
- `plugins/specclaw/bin/specclaw-presets` (new)
- `plugins/specclaw/bin/specclaw-init`
- `plugins/specclaw/skills/build/SKILL.md`
- `plugins/specclaw/skills/init/SKILL.md`
- `plugins/specclaw/templates/presets-README.md` (new)
- `plugins/specclaw/tests/run-preset-check-tests.sh`
- `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (version bump)
