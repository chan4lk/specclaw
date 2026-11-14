# Proposal: Core guards (branch, done) and the PR size cap

**Created:** 2026-11-14
**Status:** ✅ Approved 2026-11-14
**Feature:** devloop
**Depends on:** none

## Problem

Three loop rules that ION-TBML-SUITE enforces in code (ADR-0017 D4, decisions 21 and 27) are left to memory in specclaw:
- Nothing stops an agent from editing on the base branch.
- Nothing stops a turn from ending while a change whose tasks are all ticked still lacks its verify verdict
  or review verdict.
- Nothing caps the size of a PR, even though small PRs are what keep review rounds short.

## Proposed Solution

1. **Branch guard:** the existing propose gate in the core mod (`hooks/register.tsx`, modes
   `warn|block|off`) also checks the current branch. An edit outside `.specclaw/` while on the base branch
   gets the gate's toast or denial: "create a change branch first".
2. **Done guard:** a `Stop` hook. For each active change on this branch whose tasks are all done but whose
   verify verdict (and, when `specclaw-review` is installed, review verdict) is missing or not PASS for
   HEAD, it names the missing step on stderr and exits 2. A Stop already held by this hook
   (`stop_hook_active`) exits 0. It only looks at changes touched since the merge-base with the base branch,
   as TBML's `done-guard.sh` does.
3. **Size cap:** `specclaw-verify` counts production lines added and deleted against the merge-base, leaving
   out tests, `.specclaw/`, lockfiles and generated files. Over `pr.size_cap` (default 400, `0` = off), verify
   FAILs unless the proposal carries a `Size waiver: <reason>` line. Over half the cap, it prints a
   "consider splitting" note.

## Scope

### In Scope
- Branch check in the mod gate; `hooks/done-guard` and its registration; size count in `specclaw-verify`; the
  `pr.size_cap` config key; tests for each

### Out of Scope
- git `pre-push` hooks and CI steps (064)
- Counting tooling code separately (TBML's amendment): one cap, with the exclusions configurable

## Impact

- **Size:** bounded — extends the existing mod gate and `specclaw-verify`, plus one hook
- **Files affected:** ~8
- **Complexity:** medium
- **Risk:** medium. A wrong done guard traps the turn. It exits 0 on any internal error, and
  `stop_hook_active` keeps it from holding the same turn twice.

## Open Questions

- Default cap: TBML uses 200, counting tooling. 400 is proposed for a generic default. Which?
- Codex reads `hooks.json` with no mod: should the done guard be registered there too (it is a plain command hook)?

---

**To proceed:** Review this proposal and approve to begin planning.
