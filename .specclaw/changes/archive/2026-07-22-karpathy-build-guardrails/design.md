# Design: Adopt Karpathy CLAUDE.md guardrails for build (and adjacent phases)

**Change:** karpathy-build-guardrails
**Created:** 2026-05-20

## Technical Approach

The implementation is **additive and shell-only**:

1. Vendor Karpathy's four-rule CLAUDE.md verbatim into a new reference file
   under `plugins/specclaw/references/`. Add a one-paragraph attribution
   header and a one-paragraph "How specclaw uses this" footer that ties the
   rules to specclaw concepts (declared `files:` list, spec acceptance
   criteria).
2. Modify `plugins/specclaw/bin/specclaw-build-context` to read that file at
   the start of prompt assembly and inject its contents as the first section
   of the agent payload (above "Your Task"). Resilient to a missing file —
   warn-and-continue, never abort.
3. Add short cross-references in three SKILL.md files (`build`, `plan`,
   `verify`) so operators know the guardrails exist and which rules apply
   where.
4. Bump version `0.3.3 → 0.4.0` in both plugin.json and marketplace.json, and
   add a CHANGELOG entry.

No new tooling, no config flags, no schema changes. The only behavioral change
is the prompt that coding agents receive.

## Architecture

```
plugins/specclaw/
├── bin/
│   └── specclaw-build-context          [modified: prepends guardrails]
├── references/
│   ├── agent-guardrails.md             [new]
│   └── build-engine.md
└── skills/
    ├── build/SKILL.md                  [modified: link to guardrails]
    ├── plan/SKILL.md                   [modified: link rules 1 & 2]
    └── verify/SKILL.md                 [modified: link rule 4]

.claude-plugin/marketplace.json         [modified: version bump]
plugins/specclaw/.claude-plugin/plugin.json  [modified: version bump]
CHANGELOG.md                            [modified: 0.4.0 entry]
```

The injection point in `specclaw-build-context` is the final heredoc at line
~326. The cleanest insertion is to:

- Compute `GUARDRAILS_FILE="$SCRIPT_DIR/../references/agent-guardrails.md"`
  near the top alongside the other path resolutions.
- Read its contents into `GUARDRAILS_CONTENT` early (after the spec/design
  reads, around line ~208). On `[[ ! -f ... ]]`, warn to stderr and set
  `GUARDRAILS_CONTENT=""`.
- In the heredoc, add a `## Agent Guardrails\n${GUARDRAILS_CONTENT}\n` block
  **before** `## Your Task`. When `GUARDRAILS_CONTENT` is empty, the section
  collapses to just a header — acceptable; alternative is to wrap the whole
  block in a conditional pre-built string. **Decision:** use a pre-built
  string so the section disappears entirely when the file is missing
  (cleaner output).

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/references/agent-guardrails.md` | create | Vendored Karpathy rules + attribution header + specclaw footer (~80 lines). |
| `plugins/specclaw/bin/specclaw-build-context` | modify | Read guardrails file, inject as `## Agent Guardrails` section above `## Your Task` in the emitted prompt. Warn-and-continue on missing file. |
| `plugins/specclaw/skills/build/SKILL.md` | modify | Add "Agent guardrails" bullet under "Key Principles" pointing at the reference. |
| `plugins/specclaw/skills/plan/SKILL.md` | modify | Add a one-line note citing rules 1 & 2 when generating tasks. |
| `plugins/specclaw/skills/verify/SKILL.md` | modify | Add a one-line note framing verify as rule 4's goal-check loop. |
| `CHANGELOG.md` | modify | New `## [0.4.0] — 2026-05-20` entry. |
| `plugins/specclaw/.claude-plugin/plugin.json` | modify | `"version": "0.3.3"` → `"0.4.0"`. |
| `.claude-plugin/marketplace.json` | modify | Same version bump for the same plugin entry. |

## Data Model Changes

None. No new state, no new config keys, no schema changes.

## API Changes

- `specclaw-build-context` — no CLI signature change. Stdout output gains a
  new `## Agent Guardrails` section as the first block of the prompt.
  Downstream consumers (the coding agents) treat it as additional context,
  not a structured field.

## Key Decisions

- **Vendor verbatim, not fetch at runtime.** Builds must work offline; we
  don't want upstream churn to silently change agent behavior. Trade-off:
  manual re-sync if upstream evolves — accepted, it's ~50 lines.
- **Always-on, no config flag.** Per the proposal review. Avoids two-mode
  testing surface.
- **Inject in `specclaw-build-context`, not in each SKILL.md.** Single
  injection point = consistent across all coding spawns and easy to audit /
  revert. Avoids drift between skills.
- **Warn-and-continue on missing guardrails file** rather than abort. The
  build is more valuable than the guardrails; a missing file is a packaging
  bug, not a build-blocking error.
- **Version bump to 0.4.0, not 0.3.4.** This changes the prompt every coding
  agent sees — small file change, real behavioral surface. Minor-version
  signals "new behavior, not just a fix."
- **No edits to existing context-builder structure beyond the injection.**
  Honors the very rule we're adopting ("Surgical Changes").

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Heredoc breakage from backticks/`$` in vendored text | medium | build-context emits malformed prompt | Interpolate via `${GUARDRAILS_CONTENT}` variable, not literal heredoc inclusion. Sanity-check stdout in AC2. |
| Vendored text drifts from upstream over time | low | stale guidance | Note upstream URL + commit SHA in the reference header so future maintainers can re-sync. |
| Per-agent token overhead noticeable on large changes | low | marginal cost | Keep reference under 100 lines (NFR3). |
| `SCRIPT_DIR/../references/` path wrong under symlink-based plugin install | low | guardrails always missing → silent quality regression | Mirror the existing `$SCRIPT_DIR` pattern (already battle-tested for `specclaw-parse-tasks`); AC3 verifies the warning path; AC2 verifies the happy path. |
| Operators surprised by changed agent prompts | low | confusion | CHANGELOG entry + reference file + skill doc updates are the documentation trail. |
