# Design: Grounded Context Discovery

**Change:** grounded-context
**Created:** 2026-07-16

## Technical Approach

One new bash script owns all discovery logic; existing payload builders and the plan skill consume its output. Two script modes keep responsibilities clean:

- `specclaw-discover-context <specclaw_dir> list` — emit ranked candidate table (`rank<TAB>lines<TAB>path`), applying config precedence and default exclusions. Cheap; no file contents.
- `specclaw-discover-context <specclaw_dir> emit [--budget N]` — emit the concatenated digest: per-file delimited sections in rank order up to the line budget, followed by a `<!-- dropped: ... -->` footer naming anything dropped/truncated.

Payload builders (`specclaw-build-context`, `specclaw-verify-context`) call `emit` and append the digest as a delimited section. The plan skill calls `list` first (so the planning agent can reason about candidates), then `emit` for the digest, and records the selection in `design.md` ("Grounding sources").

Config parsing reuses the existing `yaml_val`-style helpers already present in `bin/` scripts (no new YAML dependency). Pattern matching uses bash `case`/glob plus a small normalization for `./root-relative` — no regex engine dependency.

## Architecture

```
config.yaml (context: block)
        │
        ▼
specclaw-discover-context ──list──▶ plan skill (survey + candidate reasoning)
        │                              │
        └──emit(budget)──┬─────────────┘ (digest → plan payload, selection → design.md)
                         ├──▶ specclaw-build-context  (after context.md + knowledge base)
                         └──▶ specclaw-verify-context (verify + code-review payloads)
```

Ranking pipeline inside the script:
1. Enumerate: `git ls-files -z -- '*.md' 'llms.txt' 'llms-full.txt'` (fallback: `find` with prune list) — null-delimited for space-safe paths.
2. Filter: default exclusions → config `exclude` → config `folders` (precedence order; `pin` bypasses).
3. Rank: tier 1 `llms.txt` entries (existing paths only) → tier 2 root canonical names → tier 3 doc dirs → tier 4 nested README/CLAUDE → tier 5 other; alphabetical within tier.
4. Budget (emit mode): accumulate `wc -l` per file in rank order; truncate boundary file; name all casualties in footer.

Codebase survey (plan skill step, not the script): `git ls-files` top-2-level directory summary + detected manifest files (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `*.csproj`, `pom.xml`, `Makefile`...) + test-directory globs. Prose instructions in SKILL.md, mirroring how build's payload steps are specified.

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-discover-context` | create | Discovery script: list + emit modes, ranking, exclusions, budget |
| `plugins/specclaw/templates/config.yaml` | modify | Add `context:` block (discovery, max_lines, folders, pin, exclude) with comments |
| `plugins/specclaw/skills/plan/SKILL.md` | modify | Codebase survey step, discovery injection, spec-guidelines.md injection, "Grounding sources" in design.md |
| `plugins/specclaw/bin/specclaw-build-context` | modify | Append "Discovered project docs" section after knowledge base, budget-capped |
| `plugins/specclaw/bin/specclaw-verify-context` | modify | Same digest section for verify/review payloads |
| `plugins/specclaw/tests/run-parser-tests.sh` | modify | New cases: ranking, llms.txt, exclusions, precedence, budget, discovery-off, non-git fallback |
| `plugins/specclaw/tests/fixtures/` | create | Fixture tree with root/nested/doc-dir markdown, llms.txt, excluded names |
| `README.md` | modify | Document context block + discovery; refresh stale config/structure sections |
| `CHANGELOG.md` | modify | 0.5.x entry |
| `plugins/specclaw/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` | modify | Version bump (final task) |

## Data Model Changes

New optional `context:` config block (additive; absent = defaults, no migration):

```yaml
context:
  discovery: true
  max_lines: 3000
  folders: []
  pin: []
  exclude: []
```

No changes to change-artifact schemas. `design.md` gains a conventional "Grounding sources" section (prose convention in plan SKILL.md, not a template field — keeps template backward-compatible).

## API Changes

New script CLI (internal API):

```
specclaw-discover-context <specclaw_dir> list
specclaw-discover-context <specclaw_dir> emit [--budget N]   # N overrides context.max_lines
```

Exit 0 always when discovery is off or nothing found (empty stdout); nonzero only on usage errors. Existing script CLIs unchanged.

## Key Decisions

1. **Candidates + LLM selection over embeddings** — Context7-style relevance reranking achieved by giving the planning agent the ranked list; zero infra, fits plugin's bash-only bar.
2. **Exclude > folders > include precedence** (Context7 evaluation order) — deterministic, easy to test, matches user intuition ("exclude always wins").
3. **`.specclaw/` excluded by default** — change artifacts and context.md must not self-inject (context.md has its own injection path with its own cap).
4. **Recompute live, record selection** — no cache file; `design.md` "Grounding sources" is the paper trail; git history shows drift.
5. **Digest after context.md and knowledge base** — curated sources outrank discovered ones in both order and budget priority (spec FR8/FR9, proposal Q2 resolution).
6. **Two-mode script** — `list` keeps plan-time reasoning cheap; `emit` keeps payload builders one-call simple.

## Grounding sources

Docs consulted while designing this change (recorded per the convention this change introduces):

- `CLAUDE.md` — version-bump rule drove task ordering (T6 last): "Always bump the plugin version before opening a PR."
- `plugins/specclaw/CLAUDE.md` — curated-doc priority (design decision 5) rests on: "`context.md` is always current. It is not an append log."
- `CONTRIBUTING.md` — test expectation: "Testing — Real-world project testing across different stacks" → jq-free Case 6 suite.
- `plugins/specclaw/references/build-engine.md` — injection mirrors the documented payload-section architecture (Repo Knowledge Base pattern).
- `.specclaw/learnings.md` — NFR1 portability bar from L2: "BSD-sed portability" and L3: "`set -e`/pipefail silent-exit in grep pipelines."

## Risks & Mitigations

- **Payload bloat on doc-heavy repos** → hard `max_lines` budget, truncation footer, curated-first ordering; default 3000 lines ≈ safe for all current model contexts.
- **Noisy/low-value docs injected** (generated API docs in `docs/`) → default exclusions + user `exclude` patterns; tier ordering puts canonical guides first so noise drops first under budget.
- **Pattern-matching bugs (glob edge cases)** → dedicated test cases per pattern type (AC4); keep supported pattern set small and documented.
- **BSD/GNU portability regressions** → follow repo learnings (no `sed -i` differences, no `set -e` grep pipelines); test suite runs the script end-to-end.
- **Behavior drift when discovery off** → AC6 byte-identical assertion in tests.
