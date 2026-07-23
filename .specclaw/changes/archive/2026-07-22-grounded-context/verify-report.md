# Verification Report: grounded-context

**Verified:** 2026-07-16
**Model:** claude-fable-5
**Verdict:** PASS

## Acceptance Criteria

- ✅ **AC1 — Ranking tiers.** Test Case 6a asserts exact ranked order on the fixture tree: `docs/guide.md` (tier 1 via llms.txt), `CLAUDE.md`/`README.md` (tier 2), `docs/skip.md` (tier 3), `src/README.md` (tier 4). Deterministic (rank then alphabetical). PASS.
- ✅ **AC2 — llms.txt priority + missing-entry warning.** Case 6a shows the llms-listed file outranking root canonical docs; Case 6b asserts the `docs/nope.md` missing-entry warning on stderr. PASS.
- ✅ **AC3 — Default exclusions.** Case 6c asserts `CHANGELOG.md` and `archive/old.md` never appear; live run on this repo confirms `.specclaw/` content absent (Case 6g asserts it explicitly). PASS.
- ✅ **AC4 — Filter precedence + pattern forms.** Case 6d: with `folders: [docs]` and `exclude: [docs/skip.md]`, only `docs/guide.md` survives (exclude beats folders). Second assertion covers root-relative (`./README.md`) and segment (`src`) patterns. PASS. (Testing this caught and fixed an inverted-return bug in `outside_folders()` — see Issues.)
- ✅ **AC5 — Budget accounting.** Case 6e: `emit --budget 4` emits exactly the two files that fit (2+2 lines) and the footer names all three casualties (`README.md`, `docs/skip.md`, `src/README.md`). PASS.
- ✅ **AC6 — Zero-break when off.** Case 6f: discovery off → empty stdout, exit 0. Additionally verified end-to-end: `specclaw-build-context` output at pre-change commit (23f5ae4~1) vs current, same inputs, discovery off — **byte-identical** (`diff` clean, 287 = 287 lines). PASS.
- ✅ **AC7 — Plan grounding steps.** `skills/plan/SKILL.md` step 3 now includes the codebase survey, `discover-context list`/`emit` usage, and the design.md "Grounding sources" requirement; this change's own `design.md` carries the section (self-compliant). PASS.
- ✅ **AC8 — Build payload injection.** Live payload for T1 on this repo shows `## Discovered Project Docs` at line 95, after Agent Guardrails / Repo Knowledge Base / Project Context, budget-capped. PASS.
- ✅ **AC9 — spec-guidelines.md injection.** Plan skill step 3 reads `.specclaw/knowledge/spec-guidelines.md` when present (previously written by `learn --promote`, read by nothing). PASS.
- ✅ **AC10 — Test suite.** `bash plugins/specclaw/tests/run-parser-tests.sh` → **24 passed, 0 failed** (13 pre-existing + 11 new Case 6 assertions), with jq installed. PASS.
- ✅ **AC11 — Docs + version.** README "Grounded Context Discovery" section + config example updated; CHANGELOG 0.5.1 entry; version 0.5.1 in `plugin.json` and `marketplace.json` (in sync). PASS.
- ✅ **AC12 — Evidence citation.** Live build payload shows the citation instruction inside "## Discovered Project Docs" ("cite the exact source: name the doc path and quote the relevant line(s)"); verify-context carries the equivalent instruction; plan skill requires quoted citations in spec/design decisions and cited "Grounding sources" entries (this change's design.md upgraded to quoted citations as the exemplar). Suite re-run after the change: 24/24. PASS.

## Test Results

```
$ bash plugins/specclaw/tests/run-parser-tests.sh
...
24 passed, 0 failed  (exit 0)
```

No project `build.test_command` is configured; the suite above is the repo's test entry point. `bash -n` syntax checks pass on all three touched bin scripts.

## Issues Found

1. **Fixed during build (T2):** `outside_folders()` in the new script had inverted return semantics — the `folders` include-filter excluded exactly the files it should keep. Caught by test 6d, fixed in the same task, regression-locked.
2. **Pre-existing, out of scope (logged):** `yaml_get` in `specclaw-build-context` does not strip inline comments — `commit_prefix` renders as `"specclaw"       # Prefix for auto-commits` in payload commit instructions. Predates this change (`yaml_val` in validate-change handles comments; `yaml_get` does not). Left untouched per surgical-changes rule; candidate for a lifecycle-bug-fixes follow-up.
3. **Environment note:** pre-existing test cases 1–5 require `jq`; machine initially lacked it (installed during verification). The new Case 6 assertions are deliberately jq-free.

## Context Compliance

`.specclaw/context.md` does not exist in this repo — no context rules to check. Repo conventions from CLAUDE.md honored: feature branch (`specclaw/grounded-context`), per-task commits with specclaw prefix, version bumped in both files as separate final task.

## Summary

**Passed:** 12/12 criteria
**Failed:** 0/12 criteria
**Verdict:** PASS
