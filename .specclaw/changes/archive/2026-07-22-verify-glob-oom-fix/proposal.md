# Proposal: Fix infinite-loop OOM in specclaw-verify path extraction

**Created:** 2026-07-18
**Status:** 🟡 Draft

## Problem

`specclaw-verify` extracts file paths from each `**Files:**` field in `tasks.md` with a loop that strips each matched backtick-quoted token off the front of the line (`plugins/specclaw/bin/specclaw-verify`, ~L118–122):

```bash
while [[ "$paths_str" =~ \`([^\`]+)\` ]]; do
  file_paths+=("${BASH_REMATCH[1]}")
  paths_str="${paths_str#*\`${BASH_REMATCH[1]}\`}"
done
```

The strip `${paths_str#*\`${BASH_REMATCH[1]}\`}` interpolates the captured path **unquoted** into a `${var#pattern}` prefix-removal pattern, so the path is **glob-interpreted**, not matched literally. When a path contains glob metacharacters, the pattern fails to match and the strip is a no-op:

- Next.js dynamic-route files — `app/[id]/page.tsx`, `app/[...slug]/route.ts` — `[id]` is a bracket character class matching a single char, not the literal 4-char text.
- Any path with `?` or `*`.

When the strip does nothing, `paths_str` never shrinks, the `=~` test keeps matching the **same** first backtick pair, and the loop appends the same path forever — unbounded array growth until the process is **OOM-killed**.

Why it matters: any specclaw change whose `tasks.md` lists a bracketed/globby path (routine in Next.js, SvelteKit, Remix, and other file-based routers) hangs `/specclaw:verify` and takes down the host with an OOM. It is silent — no error, just a runaway process — and blocks the entire lifecycle at the verify gate.

## Proposed Solution

Make the strip glob-safe so the loop always advances regardless of path content. Strip up to and including the two backticks independent of the captured text:

```bash
while [[ "$paths_str" =~ \`([^\`]+)\` ]]; do
  file_paths+=("${BASH_REMATCH[1]}")
  paths_str="${paths_str#*\`}"   # drop up to & incl the opening backtick
  paths_str="${paths_str#*\`}"   # drop the path and its closing backtick
done
```

This never depends on the captured content, so glob metacharacters can't defeat it. (Alternative: quote the token — `${paths_str#*\`"${BASH_REMATCH[1]}"\`}` — but the two-strip form is simpler and content-agnostic.)

Add a regression test: a `tasks.md` with a `**Files:**` field referencing `app/[id]/page.tsx` must make `specclaw-verify` path extraction terminate and return the literal path.

## Scope

### In Scope
- Fix the glob-unsafe strip in the backtick-extraction loop in `specclaw-verify`.
- Audit the sibling comma-separated fallback path in the same function for the same class of bug.
- Regression test covering a bracketed/dynamic-route path.
- Version bump per project rule.

### Out of Scope
- Rewriting path parsing / `tasks.md` format.
- Auditing every `${var#...}` / `${var%...}` across all `specclaw-*` scripts (candidate for a follow-up hardening pass — flag to pattern registry).
- Any change to `/specclaw:verify` acceptance-criteria logic beyond path extraction.

## Impact

- **Files affected:** 1 code + 1 test (estimated)
- **Complexity:** small
- **Risk:** low (localized; behavior-preserving for non-glob paths, fixes hang for glob paths)

## Open Questions

- Should the broader `${var#unquoted}` audit be a separate proposal, or folded in here as a bounded sweep of the verify script only? (Leaning separate — keeps this fix minimal.)
- Any other lifecycle script that parses backtick-quoted paths from markdown the same way (e.g. `specclaw-build-context`, `specclaw-gh-sync` checklist builders)? Worth a quick grep before closing.

---

**To proceed:** Review this proposal and approve to begin planning.
