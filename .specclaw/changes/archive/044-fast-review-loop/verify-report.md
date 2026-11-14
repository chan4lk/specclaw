**Verdict:** PASS

# Verification Report: 044-fast-review-loop

**Verified:** 2026-10-16
**Model:** claude-opus-5-5
**Verdict:** PASS on the local evidence. All 27 ACs are met. GitHub CI on Linux has not run yet and is the deciding gate.

**Re-check note:** I re-checked only AC-23 and AC-8 against your fixes; the other 25 ACs carry over from my first run. Both fixes sit in uncommitted edits to `spec.md` and `smoke-replay.md`, so they need committing before the PR.

## Acceptance Criteria

| AC | Result | Evidence |
|---|---|---|
| AC-1 | MET | Tests pass: `AC-1 base, then preset pack, then repo rules, then overrides` and `AC-1 unknown pack is a note, not a failure`. |
| AC-2 | MET | Tests pass for code → `review` and records/docs-only → `skip`. Risky paths are collected in `classify()` (`review_core.py:~263`), and the final model is used when they match. No dedicated test asserts the risky-path model choice (see Concerns). |
| AC-3 | MET | Tests pass: `major with scenario exits 1 and writes round-1.json` and `minors only exits 0 and lands in follow-ups.md`. |
| AC-4 | MET | Tests pass: `backend failure exits 3, status not_run` and `prose with no JSON array exits 3, verdict never clean`. Code: `run_round`'s `except ReviewError` sets `rec["status"]="not_run"` when the code is 3. |
| AC-5 | MET | The AC-5 test passes. It covers the scenario-less major, the doc-file cap, duplicate collapse, and pre-existing findings not being counted. |
| AC-6 | MET | Test `--since lists the PR's own fix, not the merged base file` passes. The test only checks `classify`'s file list. `diff_text` uses the same `log -p --no-merges --first-parent since..HEAD -- files`, so merged base content cannot enter the prompt diff. |
| AC-7 | MET | Test `impact set lists b.py (calls helper_fn)` passes. |
| AC-8 | MET (re-checked) | Spec AC-8 and FR-3 exit 4 now read "the same rule in the same file … keyed on rule + file". That matches the code at `review_core.py:619-622` (`seen.setdefault((f.get("rule"), f["file"]), …)`, `repeat = … >= 2`), and the test `third round with the same finding escalates (exit 4)` passes. |
| AC-9 | MET | Four AC-9 tests pass: no final pass → not OK; final pass at HEAD → OK; a records-only commit after the final pass → still OK; a code commit after the final pass → not OK. |
| AC-10 | MET | The AC-10 test passes. It covers dedupe, the budget with 5,000 entries, and compaction. |
| AC-11 | MET | Three AC-11 tests pass: every file tool and Bash is denied on the memory path, unrelated paths and `git add` are allowed, and the deny reason names `memory_query`. |
| AC-12 | MET | Test `initialize, tools/list (10 tools), memory_query call` passes. The AC text says 9 tools; AC-26 raises that to 10. |
| AC-13 | MET | Four AC-13 tests pass: learn dry-run, learn `--apply`, import dry-run, and import `--apply` with a source header. |
| AC-14 | MET | Test `stats prints median rounds and per-model rates` passes. |
| AC-15 | MET | Test `rules dir, memory dir, one .gitattributes line, claude rule` passes. |
| AC-16 | MET | Three AC-16 tests pass. In `specclaw-pr` and `specclaw-azdo-pr`, `review_line` stays `""` unless `command -v specclaw-review` succeeds, and `**Verdict:** ${verdict}${review_line}` expands to the original text, so output is byte-identical. That byte-identity was confirmed by reading the code, not by a run without the plugin. |
| AC-17 | MET | Every `.claude-plugin`/`.codex-plugin` manifest and every `.claude-plugin/marketplace.json` entry is at 0.8.2, and `.agents/plugins/marketplace.json` has a specclaw-review entry. The AC-17 test passes, and `run-codex-plugin-tests.sh` exits 0. |
| AC-18 | MET | `smoke-replay.md` §5 records a local real-backend replay of PR-A (Haiku 115 s, Sonnet 69 s) that exercised round records, verdict and stats. This is a recorded claim and cannot be re-run offline. |
| AC-19 | MET | Both AC-19 tests pass: two passes make two backend calls, findings are tagged by pass and collapsed across passes, and the same symbol collapses even when the lines are far apart. |
| AC-20 | MET | Test `default backend argv: tools, turns, system file, dontAsk; none → --tools ""` passes. |
| AC-21 | MET | Test `governance file is in the rulebook, read live` passes. An edit to the governance file shows up in the next rulebook with no import step. |
| AC-22 | MET | Both AC-22 tests pass: the README hunk is in the diff with findings capped at minor, and a docs-only change classifies as `skip`. |
| AC-23 | MET (re-checked) | See below. |
| AC-24 | MET | Test `severity: project keeps a scenario-less major and drops the scenario gate from the prompt` passes. The governance-set default is described in FR-23. |
| AC-25 | MET | Both AC-25 tests pass. They cover governance by category, the exclusions, the severity flag, the suggested block, and that nothing is written. |
| AC-26 | MET | Test `over budget warns; --json is valid JSON` passes, and the MCP test asserts 10 tools. |
| AC-27 | MET | Five FR-24 tests pass: an option-like `--since` is refused, unknown severity and missing file are kept, a still-open finding is not re-counted, a rebased-away final pass gives exit 1 with a reason, and the guard allows the rule file and guards a configured `memory_dir`. |

**Why AC-23 is now met:** spec AC-23 now says "PR A at its first-iteration head", and `smoke-replay.md` has a new section "## 2b. PR-A in match-Project-A mode (AC-23)".
- **Setup:** it lists every match-mode condition the AC names: Opus, `passes: [review, design]`, `Read,Grep,Glob` with 12 turns, and the 11 server governance files read live.
- **Comparison:** each local round is set against the server's 5 distinct round-1 major issues. Opus re-found 4 of 5, one of them only at minor. Sonnet re-found 4 of 5 at major. Haiku re-found 3. Issue 5 was missed by all three.
- **Evidence status:** like AC-18, this comes from runs earlier in the session and cannot be re-run offline.

## Tests

- **Plugin suite.** I ran `bash plugins/specclaw-review/tests/run-review-tests.sh`: 46/46 PASS, exit 0. It is registered in `.github/workflows/ci.yml` as "Run specclaw-review tests". The fixes touched only docs, so I did not run it again.
- **Full CI suite run locally on macOS** (`ci-results.txt`): 36 pass, 15 fail. The failing set is identical to the one from a clean `main` checkout on this machine (`main-results.txt`), so the failures come from this macOS environment and are not regressions. They are:
  - `specclaw/`: parser, long-orchestration, synth-agent, phase-state, change-numbering
  - `specclaw-bf/`: replay-classification, blueprint, bf-status, quality, and five prototype-* suites
  - `specclaw-extras/`: party
- **The suites this change touches all pass:** headless-pr, azdo-pr-description, plugin-split, codex-plugin, shellcheck-gate and review.
- **GitHub CI (Linux) has not run on the PR yet.** It is the deciding gate, and this PASS depends on it passing.

## Code review (the 6 WARNs from `review-report.md`, all fixed in b0df9c9)

1. **`since` argument injection: FIXED.** `resolve_since()` at `review_core.py:235-245` rejects a leading `-`, resolves with `rev-parse --verify --quiet --end-of-options <since>^{commit}`, and requires a hex sha. Both `changed_files` and `diff_text` call it. A test covers it.
2. **Findings silently dropped: FIXED.** `parse_findings` at `review_core.py:516-521` maps unknown severities through `SEVERITY_ALIASES` (default `major`) and sets a missing file to `"(unspecified)"`, so it never drops a finding. A test covers it.
3. **Verdict exits 2 after a rebase: FIXED.** `review_core.py:663-669` checks `merge-base --is-ancestor` first and gives `ok=False` with a reason when the final pass is unreachable. A test covers it.
4. **Memory counts inflate across rounds: FIXED.** `review_core.py:628-630` skips fingerprints already seen in earlier rounds of this change. A test covers it.
5. **Guard ignores the configured `memory_dir`: FIXED.** `hooks/guard-memory:19-32` reads `review.memory_dir` from the config, and line 51 matches the directory as a path segment, so `specclaw-review-memory.md` is no longer denied. A test covers it.
6. **Spec drift on default models: FIXED.** FR-7 now says sonnet/opus and cites `smoke-replay.md`, which matches `review_core.py:148`.

The NOTEs about the MCP server crashing (`server.py:94` now catches `Exception`) and the `pr.md` step numbering were also fixed. The escalation-key NOTE is now closed in the spec, as described under AC-8.

## Concerns (none blocking)

- **Uncommitted fixes.** The AC-8 and AC-23 fixes exist only as uncommitted edits to `spec.md` and `smoke-replay.md`. They need committing before the PR.
- **No-op flags.** `--pr-line` and `--check-head` are accepted by `bin/specclaw-review` but never read, though the CI snippets pass `--check-head` as if it did something. The output is still correct.
- **`stats` re-parses its own output.** `review_core.py:705` parses strings it built a few lines earlier, which is fragile.
- **Guard error handling.** `guard-memory` catches only `OSError`/`ImportError`. A config parse error of another type would crash the hook, and Claude Code would then allow the call (fail-open).
- **Untested paths.** The risky-path → final-model choice (AC-2) and AC-16's byte-identity without the plugin have no executed test; both rest on reading the code.
- **Replay evidence.** AC-18 and AC-23 rest on recorded replay tables from earlier in the session. They cannot be re-run offline, and no round files are attached.

## Summary

**Passed:** 27/27. **Failed:** 0/27. **Verdict:** PASS, pending Linux GitHub CI and a commit of the two uncommitted record fixes.

**Post-verify:** the uncommitted AC-8/AC-23 record fixes and a guard fail-open hardening (any config error keeps the default marker) were committed with this report; the plugin suite still passes 46/46.

**Code Review:** APPROVED_WITH_NOTES — 11 findings: 0 BLOCK, 6 WARN (all fixed in b0df9c9), 5 NOTE (3 fixed, 2 open: no-op `--pr-line`/`--check-head` flags, `stats` re-parsing its own output)
