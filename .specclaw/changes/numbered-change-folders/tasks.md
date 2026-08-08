# Tasks: Numbered change folders

**Change:** numbered-change-folders
**Created:** 2026-08-08
**Total Tasks:** 6

## Summary

Two new `bin/` scripts, a numeric sort threaded into two existing ones, skill wiring, one new test suite registered in CI, and docs plus the version bump. Six tasks in three waves. Wave 1 is the two independent code changes; wave 2 builds on the numbering helper; wave 3 tests and documents the finished behaviour.

## Tasks

### Wave 1 — Independent foundations

- [x] `T1` — `specclaw-next-change-number`
  - Files: `plugins/specclaw/bin/specclaw-next-change-number` (create)
  - Estimate: small
  - Kind: impl
  - Notes: Glob `changes/*/` and `changes/archive/*/`, basename, match `^[0-9]+`, print `max+1` as `printf '%03d'`. Force base ten with `10#` on *every* numeric comparison — `$((08))` is a bash syntax error and a folder named `008-foo` would abort the script. Skip non-matching names and the literal `archive` directory rather than erroring; mixed numbered/unnumbered is a supported state. Empty `changes/` prints `001`. Must survive `archive/` not existing. Satisfies FR1–FR5.

- [x] `T2` — Numeric ordering in `update-status` and `reconcile`
  - Files: `plugins/specclaw/bin/specclaw-update-status`, `plugins/specclaw/bin/specclaw-reconcile`
  - Estimate: small
  - Kind: refactor
  - Notes: Both iterate `for d in "$DIR"/*/` today, which is lexical — `010-a` sorts before `002-b`. Sort numbered folders ascending by number and emit unnumbered ones *after* them, not interleaved at position zero. Also add the FR17 hint line to `update-status`: one line naming the count of unnumbered folders and `/specclaw:renumber`, emitted only when that count is non-zero. Keep the existing `archive` skip and the fail-open `state.json` handling intact. Satisfies FR16, FR17.

### Wave 2 — Backfill and wiring

- [ ] `T3` — `specclaw-renumber-changes`
  - Files: `plugins/specclaw/bin/specclaw-renumber-changes` (create)
  - Estimate: large
  - Kind: migration
  - Depends: T1
  - Notes: Three phases, strictly ordered — plan, validate, execute — with every refusal before the first rename, so a failure stops early rather than clobbering halfway. Plan: resolve each folder's date from `**Created:**` in `proposal.md`, else git first-commit date, else a leading `YYYY-MM-DD-` on the name, else sort last; tie-break by name for determinism. Strip any leading `YYYY-MM-DD-` when forming the new slug, or the backfill preserves the misleading prefix this change exists to remove. Validate: refuse if any folder is already numbered (unless `--force`), if any change is mid-build per `git worktree list` / current branch, or if any planned target already exists. Execute only under `--apply`: `git mv` in a working tree, `mv` outside one. After each rename, if `state.json` exists, refresh its `change` field by re-invoking `specclaw-set-phase <dir> <new-name> <current-phase> <current-status>` — read phase and status back from the file first. **Never edit `state.json` directly**; `set-phase` is the only sanctioned writer, equal-rank transitions are allowed so no `--force` is needed, and it preserves `at` timestamps. Satisfies FR8–FR15.

- [ ] `T4` — Skill wiring
  - Files: `plugins/specclaw/skills/propose/SKILL.md`, `plugins/specclaw/skills/archive/SKILL.md`, `plugins/specclaw/skills/status/SKILL.md`, `plugins/specclaw/skills/renumber/SKILL.md` (create)
  - Estimate: medium
  - Kind: docs
  - Depends: T1
  - Notes: `propose` step 1 calls `specclaw-next-change-number` and prepends the result to the slug; add the one-time backfill offer — when unnumbered folders exist, show the dry-run plan and ask once, and proceed with just the new change if declined. `archive` step 4 drops the `YYYY-MM-DD-` prefix, moving to `changes/archive/<name>/` with the number preserved. `status` surfaces the hint line. New `renumber` skill wraps the script: dry-run, show plan, confirm, apply. Skills must call the helper rather than restating the number format, so the rule lives in one place. Satisfies FR6, FR7, FR18, FR19.

### Wave 3 — Verification and documentation

- [ ] `T5` — Test suite plus CI registration
  - Files: `plugins/specclaw/tests/run-change-numbering-tests.sh` (create), `.github/workflows/ci.yml`
  - Estimate: large
  - Kind: test
  - Depends: T1, T2, T3
  - Notes: Cover AC1–AC18. Priority cases: empty `changes/` → `001`; active+archive max with a gap → `008`; `008-a` present → `009` (the octal trap); `999-a` → `1000`; folders named `archive` and `archive-cleanup`; dry-run leaves the tree byte-identical; `--apply` orders by date not name; a proposal with no `Created:` line; two folders sharing a date ordering stably; already-numbered refusal and its `--force` override; target-collision abort; `state.json` `change` field updated with phase records otherwise intact and the file still parsing; `reconcile` reporting zero drift afterwards; `STATUS.md` ordering `002-b`, `010-a`, `unnumbered-c`. Bash and coreutils only — no `jq` in the suite itself. **Register the suite in `.github/workflows/ci.yml`** in the same commit; an unregistered suite silently never runs, which has happened twice in this repo. Confirm `bash plugins/specclaw/tests/shellcheck-gate.sh` exits 0 with `shellcheck-baseline.txt` unmodified.

- [ ] `T6` — Docs and version bump
  - Files: `plugins/specclaw/CLAUDE.md`, `README.md`, `docs/index.md`, `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - Estimate: small
  - Kind: docs
  - Depends: T4
  - Notes: Add both new scripts to the script table in `plugins/specclaw/CLAUDE.md` and document the numbering rule, the three-digit choice, and that backfill is opt-in. Update any shown `changes/<name>/` path in `README.md` and `docs/index.md` to the numbered form. Bump the patch version in **both** manifests and keep them identical — CI fails the `json` job on a mismatch.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Kind: docs | test | config | refactor | impl | migration   (optional; hints the build subagent's role, tools, and model)
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
