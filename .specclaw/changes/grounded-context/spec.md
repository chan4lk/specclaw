# Spec: Grounded Context Discovery

**Change:** grounded-context
**Created:** 2026-07-16
**Status:** 🟡 Draft

## Overview

SpecClaw phases (plan, build, verify/review) currently ignore documentation the host project already has. This change adds repo-wide auto-discovery of project docs and a structured codebase survey, injected into phase payloads under configurable budgets. All behavior is config-gated; defaults preserve current behavior when discovery is disabled or finds nothing. The plugin remains project-agnostic: discovery is convention-based (canonical filenames, doc directories, `llms.txt`), never tied to a language or framework.

## Requirements

### Functional Requirements

- **FR1 — Discovery script.** New `bin/specclaw-discover-context` enumerates candidate documentation files repo-wide via `git ls-files` (respecting `.gitignore`), falling back to `find` when not in a git work tree.
- **FR2 — `llms.txt` support.** If `llms.txt` or `llms-full.txt` exists at repo root, files it references (repo-relative paths that exist) are ranked highest, ahead of heuristic tiers.
- **FR3 — Ranking tiers.** Candidates rank: (1) `llms.txt`-listed → (2) root canonical names (`CLAUDE.md`, `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, `CODE-CONVENTIONS.md`, `SECURITY.md`, `docs/index.md`) → (3) files in doc directories (`docs/`, `doc/`, `.github/`, `wiki/`) → (4) nested `README.md`/`CLAUDE.md` → (5) other `*.md`. Ties break alphabetically (deterministic output).
- **FR4 — Default exclusions.** Excluded without configuration: changelog/license/code-of-conduct variants, `archive/` and `deprecated/` directories, `i18n/` and locale variants, `node_modules/`, `vendor/`, `dist/`, `build/`, and `.specclaw/` itself (change artifacts must not self-inject).
- **FR5 — Config precedence.** Evaluation order per file: `exclude` match → excluded; `folders` non-empty and file outside → excluded; otherwise included. `pin` entries bypass ranking and are always included first. Patterns support simple names (`node_modules`), root-relative (`./x`), and glob/globstar (`**/dist`).
- **FR6 — Line budget.** Total emitted content is capped by `context.max_lines` (default 3000). Over budget: drop lowest-rank first, truncate the boundary file; every dropped or truncated file is named in the output (no silent omission).
- **FR7 — Config block.** `context:` block with `discovery` (default `true`), `max_lines` (3000), `folders` ([]), `pin` ([]), `exclude` ([]). Absent block = these defaults. `discovery: false` = script emits nothing and phases behave exactly as today.
- **FR8 — Plan integration.** `/specclaw:plan` gains: (a) a structured codebase survey (directory tree summary, detected manifests/languages, test layout) in the planning payload; (b) discovered-docs digest (script output); (c) `.specclaw/knowledge/spec-guidelines.md` injected when present; (d) `design.md` records the selected docs under a "Grounding sources" section.
- **FR9 — Build integration.** `specclaw-build-context` includes the discovered-docs digest in coding-agent payloads, after `context.md` and the knowledge base, within the remaining budget.
- **FR10 — Verify/review integration.** `specclaw-verify-context` includes the digest so the verify and code-review agents see project conventions.
- **FR11 — Documentation.** README documents the `context:` block, discovery ranking, `llms.txt` support, and exclusion rules; stale adjacent sections (config examples, project structure) are refreshed. CHANGELOG entry added.

### Non-Functional Requirements

- **NFR1 — Portability.** Plain bash + coreutils; no jq dependency; BSD/GNU-sed-safe constructs only (matches existing `bin/` bar and repo learnings L1–L5).
- **NFR2 — Zero-break.** With `context.discovery: false`, or no matching docs, all phase payloads are byte-identical to current behavior (no empty section headers).
- **NFR3 — Bounded cost.** One `git ls-files` pass; no per-file subprocess loops over the whole tree; script completes in <2s on a 10k-file repo.
- **NFR4 — Project-agnostic.** No language-, framework-, or repo-specific logic; conventions only.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- [ ] **AC1** — On a fixture repo with root `README.md` + `CLAUDE.md` + `docs/guide.md` + `src/README.md`, the script lists all four, ranked tier-2, tier-2, tier-3, tier-4 respectively, deterministically.
- [ ] **AC2** — With an `llms.txt` listing `docs/guide.md`, that file outranks root canonical names; entries pointing to nonexistent files are ignored with a warning.
- [ ] **AC3** — `CHANGELOG.md`, `LICENSE.md`, `CODE_OF_CONDUCT.md`, files under `archive/`, `i18n/`, and `.specclaw/` are excluded by default.
- [ ] **AC4** — A file matched by both `folders` (include) and `exclude` is excluded (precedence holds); glob and root-relative patterns both work.
- [ ] **AC5** — With `max_lines` smaller than total candidate lines, output stays within budget, lowest-rank files drop first, and every dropped/truncated file is named in a footer.
- [ ] **AC6** — With `context.discovery: false`, the script exits 0 with empty output, and `specclaw-build-context` output is identical to pre-change output for the same inputs.
- [ ] **AC7** — Plan payload (skill steps) includes the codebase survey and discovered-docs sections when discovery is on, and a "Grounding sources" section lands in `design.md`.
- [ ] **AC8** — `specclaw-build-context` output contains a delimited "Discovered project docs" section, after Project Context and Repo Knowledge Base, capped by the budget.
- [ ] **AC9** — When `.specclaw/knowledge/spec-guidelines.md` exists, the plan payload includes it (closing the currently-dead promote path).
- [ ] **AC10** — `bash plugins/specclaw/tests/run-parser-tests.sh` passes: all pre-existing cases plus new discovery cases (ranking, exclusion, precedence, budget, non-git fallback).
- [ ] **AC11** — README documents the `context:` block and discovery behavior; CHANGELOG has an entry; plugin version bumped in both version files.

## Edge Cases

- Not a git work tree → `find`-based fallback, same exclusions applied.
- Repo with zero markdown files → empty output, no section injected (NFR2).
- Single file larger than the whole budget → truncated to budget with a named truncation notice, not silently dropped.
- `llms.txt` with URLs (not repo paths) → non-existent-path entries skipped with warning.
- Filenames with spaces → handled (null-delimited or IFS-safe iteration).
- CRLF files → line counting unaffected (`wc -l` semantics documented).
- Symlinked docs → followed only if target inside repo; broken symlinks skipped.
- `.specclaw/context.md` → never discovered (already injected separately; dedup guaranteed by the `.specclaw/` default exclusion).

## Dependencies

- None new. `git` optional (fallback exists). Existing scripts touched: `specclaw-build-context`, `specclaw-verify-context`.
- Changes `templates/config.yaml` (additive block) — no migration needed for existing projects (absent block = defaults).

## Notes

- Discovery emits *candidates + digest*; relevance selection at plan time is the planning agent's job (LLM-rerank pattern from Context7, no embeddings/infra).
- Review-integrity and review-depth features are separate follow-up changes.
