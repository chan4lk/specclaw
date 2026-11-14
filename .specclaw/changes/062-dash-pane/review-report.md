# Code Review Report: 062-dash-pane

**Reviewed:** 2026-11-14
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

4 findings: 0 BLOCK, 1 WARN, 3 NOTE

## Findings

### [WARN] plugins/specclaw-dash/hooks/register.tsx:28 — Complexity / Correctness
**Problem:** `if (/\.specclaw/i.test(JSON.stringify(e))) await refreshQuietly($)` stringifies every tool-call event, so a `Read` of a `.specclaw` file, or a tool result that mentions `.specclaw`, triggers a full refresh (the loops, the MCP call and the transcript stat walk). The refresh is also awaited before the tool result returns, so it adds latency to those calls.
**Fix:** Refresh only after writes (match the tool name or `file_path` field), or drop it, since `turn.complete` already refreshes.

### [NOTE] plugins/specclaw-dash/hooks/core/scan.ts:92 — Correctness
**Problem:** `resume = size >= prev.size && prev.offset <= text.length` treats a file rewritten to the same or a larger size as appended. Transcripts are append-only, so this is acceptable. A `shortcut:` comment would record the limit.

### [NOTE] plugins/specclaw-dash/hooks/core/scan.ts:10-19 — Correctness
**Problem:** The price table can't be verified from this repo. The cached-from-skill note is the only source, and `claude-sonnet-5` has a cache-read price of 0.2 while `claude-sonnet-5-5` has 0.1. Costs are labelled an API-equivalent estimate, and an unknown model is priced at the dearest, which is conservative.

### [NOTE] plugins/specclaw-dash/tests/pane.test.tsx:1 — Test quality
**Problem:** `bun test` run bare in the plugin dir fails: "Cannot find module 'react/jsx-dev-runtime'". `run-mod-tests.sh` runs only `./tests/*.spec.ts` and leaves `pane.test.tsx` to `claude plugin test`. All 23 spec tests pass. This is expected, but the README should say not to run bare `bun test`.

## Checked, no finding

- **Privacy:** `scanText` skips lines without `"usage":{` or `Title":`. For the rest it calls `JSON.parse` and `apply` reads only usage counts, model, id, timestamp, `gitBranch` and the title strings. `FileScan` and `Call` hold no prompt, tool or thinking text. Titles are kept deliberately (spec). Note that `custom-title` and `ai-title` are user or AI generated, so they are the only free text kept.
- **Read-only:** no `$.fs.write` or `$.process` anywhere in the mod, and `run-mod-tests.sh` greps for both. `learn_propose` is a dry run (`plugins/specclaw-review/skills/learn/SKILL.md:12`). There are no launch or approve actions.
- **Errors:** every read fails soft into a `Section` error or `missing` card. Files over 4 MiB count as skipped, and the totals say so.
- **plugins.sh:** the empty-command branch checks the manifest in the checkout and cache layouts. Callers pass `"$cmd"` quoted (`bin/specclaw-suggest:62`, `lib/plugins.sh:59`). Fine.
- **Scope:** all changed files appear in the `tasks.md` `Files:` lists.

## Verdict Rationale

No correctness, security or privacy defects. The scanner keeps only counts, ids, models and titles. The pane makes no writes and no launch or approve calls. One WARN (over-eager refresh on any tool call that mentions `.specclaw`) and a few notes remain.
