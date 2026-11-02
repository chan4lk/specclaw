# Code Review Report: 047-specclaw-mod

**Reviewed:** 2026-11-02
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

6 findings: 0 BLOCK, 3 WARN, 3 NOTE

## Findings

### [WARN] plugins/specclaw-mod/hooks/core/gate.ts:37 — Security (gate bypass)
**Problem:** `/^\.(specclaw|git)(\/|$)/.test(relative)` allows every Edit/Write under `.specclaw/`, including `changes/<x>/state.json`. The gate approves on `phases.proposal.status === 'approved'` read from that file (state.ts:48), so the agent can Write `"approved"` into state.json and then edit source. This breaks NFR-2's intent that `specclaw-set-phase` is the only phase writer. The `.specclaw` exemption is needed for the propose flow, so the hole is narrow: deny `state.json` (or `.specclaw/changes/*/state.json`) specifically. Bash writes are also ungated, but that was accepted in the spec.
**Fix:** exempt `.specclaw/` except `/state\.json$/`, or document the gate as advisory.

### [WARN] plugins/specclaw-mod/hooks/core/gate.ts:38 — Correctness (stale approval)
**Problem:** `active(snapshot.changes).some(change => change.approved)` — approval is never revoked. Any unarchived change that was ever approved (phase build, verify, pr, or abandoned) permanently opens the gate for all edits to unrelated work. Matches FR-7 literally, but in practice the gate is only effective on a project that has never approved anything.
**Fix:** consider scoping to the `current` change; at minimum note the limit in the README.

### [WARN] plugins/specclaw-mod/hooks/core/gate.ts:19-32 — Correctness (path normalisation)
**Problem:** `normalise` is lexical only. A symlink inside cwd that points outside, or at `.specclaw`/`.git`, is not resolved. A cwd of `/` makes `root + '/'` equal `'//'`, so nothing matches and every path is allowed. Backslash and Windows drive paths are treated as relative names. No bypass of the deny case was found for `..`, `.`, or duplicate slashes; tests cover `..`.
**Fix:** document the lexical-only limit (v1); no code change needed.

### [NOTE] plugins/specclaw-mod/hooks/core/state.ts:51 — Correctness (spec drift)
**Problem:** `pr: phases.pr?.url` — FR-1 also lists the top-level `.pr` field. It is ignored.
**Suggestion:** `pr: phases.pr?.url ?? json?.pr`

### [NOTE] plugins/specclaw-mod/hooks/core/state.ts:19 — Simplicity
**Problem:** `text.slice(start + 1)` skips one `#` so the heading no longer matches `/^## /m`. This is correct but obscure.
**Suggestion:** `text.slice(start).replace(/^## Tasks\s*$/m, '')`, or slice past the heading line.

### [NOTE] tasks.md T1 — Scope creep (D9)
**Problem:** T1 declares `hooks/core.ts` and `tests/core.test.ts`. The build produced `hooks/core/{gate,state,view}.ts`, `read.ts`, `fixtures.ts`, `*.spec.ts`, and `.gitignore`. This is harmless and consistent with the 80-line preset, but tasks.md is out of date.

## Verdict Rationale

The fail-open path is correct: the `.catch` guards on `next.called`, `next` is documented as replay-safe, and the gate re-reads state on each call, so there is no stale-state bug in the gate itself. Path normalisation handles `..`, relative paths, and outside-cwd targets. No BLOCK findings, because the weaknesses (state.json self-approval, sticky approval, symlinks) are spec-accepted or v1 limits. The state.json self-approval hole should still be closed or documented, as it defeats the gate for a cooperating agent. Tests cover AC1-AC7 and files stay under 80 lines with no comments.
