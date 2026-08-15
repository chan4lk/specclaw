# Proposal: Grounded Context Discovery

**Created:** 2026-07-16
**Status:** 🟡 Draft

## Problem

_What problem are we solving? Why does it matter?_

SpecClaw's planning and review phases operate with limited awareness of the host project. `/specclaw:plan` reads the proposal, `.specclaw/context.md`, and "the codebase" (unstructured guidance in the skill prose), but it never systematically discovers the documentation the project already has — root guides like `CLAUDE.md` / `README.md` / `CONTRIBUTING.md`, architecture docs, convention documents, or per-package READMEs that can live anywhere in the tree. The result: specs and designs are drafted without the project's own documented rules, and coding/review agents repeat mistakes the project has already written down how to avoid.

`context.md` partially covers this, but it is a SpecClaw-managed artifact that starts empty; it does not leverage the documentation investment a project has already made. For a plugin meant to work on any project of any type, ignoring existing docs is a systematic quality gap in every phase downstream of `propose`.

## Proposed Solution

_What are we building? High-level approach._

Add **auto-discovery of project documentation and a structured codebase survey**, injected into the planning and review payloads. All behavior is config-gated and defaults preserve current behavior when discovery finds nothing.

1. **New script `specclaw-discover-context`** — repo-wide doc discovery (conventions adapted from Context7's `context7.json` parsing model):
   - Enumerates candidate docs via `git ls-files` (respects `.gitignore`; falls back to `find` outside git).
   - **`llms.txt` convention support:** if the repo has an `llms.txt` / `llms-full.txt` index, treat it as the authoritative doc list (highest rank) before heuristic discovery.
   - Ranks candidates: (a) `llms.txt`-listed → (b) root canonical names (`CLAUDE.md`, `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, `CODE-CONVENTIONS.md`, etc. — root markdown always included) → (c) files in doc-ish directories (`docs/`, `doc/`, `.github/`, `wiki/`) → (d) nested `README.md`/`CLAUDE.md` → (e) other `*.md`.
   - **Default exclusions** (Context7-style, overridable): changelogs, licenses, code-of-conduct files, `archive/`/`deprecated/` folders, `i18n/` language variants.
   - **Config precedence** (Context7 evaluation order): `exclude` match → excluded; `folders` non-empty and file outside → excluded; otherwise included. Patterns support simple names (`node_modules`), root-relative (`./x`), and glob/globstar (`**/dist`).
   - Emits a ranked candidate list capped by a configurable line budget (`context.max_lines`, default 3000); over-budget files are truncated or dropped lowest-rank-first, and every dropped/truncated file is named in the output (no silent omission).
   - Plain bash + coreutils, jq-free, BSD/GNU-sed safe — same portability bar as existing `bin/` scripts.
   - **Relevance selection at plan time:** the script emits *candidates*; the planning agent selects which to read fully based on relevance to the change (Context7's LLM-rerank idea, no embeddings needed) and records the selection.
2. **Codebase survey step in `/specclaw:plan`** — before writing `spec.md`/`design.md`, the skill builds a structured survey (directory tree summary, detected languages/manifests, entry points, test layout) and includes it in the planning payload, replacing the current unstructured "read the codebase" prose.
3. **Payload integration** — discovered docs digest + survey are injected into: the `plan` payload (spec/design/tasks generation), `specclaw-build-context` (coding agents), and the code-reviewer/verify payloads. Each injection is clearly delimited and capped.
4. **Config block** (seeded by init, absent block = auto defaults):
   ```yaml
   context:
     discovery: true        # false = current behavior, no discovery
     max_lines: 3000        # total line budget for injected docs
     folders: []            # restrict discovery to these dirs (empty = whole repo)
     pin: []                # always-include paths (bypass ranking)
     exclude: []            # patterns to skip (simple name | ./root-relative | glob)
   ```
5. **Inject promoted spec knowledge into plan** — `.specclaw/knowledge/spec-guidelines.md` is written by `specclaw-learn --promote` but currently read by nothing. Plan payload gains it alongside discovered docs (agent-hints.md already reaches build agents; this closes the same loop for planning).
6. **Update the repo README** — document the new grounded-context behavior: `context.discovery` config block, `llms.txt` support, discovery ranking and exclusions, and how discovered docs flow into plan/build/verify. Refresh any adjacent README sections that the feature makes stale (e.g. project-structure/config examples) so the README stays accurate end-to-end.

## Scope

### In Scope
- New `bin/specclaw-discover-context` script (discover + rank + budget + emit).
- `context:` config block in `templates/config.yaml` with safe defaults.
- `plan` SKILL.md: codebase survey step + discovered-docs injection.
- `specclaw-build-context` and verify/review payload integration.
- Tests for the discovery script (fixtures with nested docs, exclusions, budget overflow) in `tests/`.
- Documentation: README section + `references/` note.

### Out of Scope
- Review-integrity features (no-false-green, `files_seen`, crid, diff caps) — separate change `review-integrity`.
- Adversarial/design-pass review depth — separate change `review-depth`.
- Any change to `context.md` semantics (living doc stays as-is; discovery complements it).
- Non-markdown doc formats (rst/adoc) — future iteration.
- External doc sources (wikis, Confluence, URLs).

## Impact

- **Files affected:** ~8 (estimated) — 1 new bin script, config template, plan SKILL.md, build-context script, verify/review payload wiring, tests, README, CHANGELOG
- **Complexity:** medium
- **Risk:** low — additive, config-gated, degrades to current behavior when no docs found or `discovery: false`

## Open Questions (resolved)

1. **Discovery at propose time?** Resolved: plan onward. Propose stays lightweight; grounding belongs where spec/design are written. Exception: root canonical docs (rank b) are cheap — propose MAY read them to avoid proposing something the project already documents as a non-goal.
2. **Budget split between `context.md` and discovered docs?** Resolved: fixed priority — curated `context.md` first (it is human/agent-curated truth), promoted knowledge files second, discovered docs fill the remaining budget in rank-then-relevance order.
3. **Cache discovery per change or recompute?** Resolved: recompute live each phase (docs move/change between phases); the plan phase records the selected doc list in `design.md` ("Grounding sources" section) for the paper trail, so drift between phases is visible in git history.

---

**To proceed:** Review this proposal and approve to begin planning.
