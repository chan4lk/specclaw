# Design: Fix infinite-loop OOM in specclaw-verify path extraction

**Change:** verify-glob-oom-fix
**Created:** 2026-07-18

## Technical Approach

Replace the glob-unsafe strip in the backtick-extraction loop of `collect_change_data` in `plugins/specclaw/bin/specclaw-verify`. The current line:

```bash
paths_str="${paths_str#*\`${BASH_REMATCH[1]}\`}"
```

interpolates the captured path into the removal pattern, so `[`, `]`, `?`, `*` in the path are glob-interpreted and the strip silently no-ops. Replace with two content-agnostic strips that always advance past the just-matched token:

```bash
paths_str="${paths_str#*\`}"   # remove up to & including the opening backtick
paths_str="${paths_str#*\`}"   # remove the path text and its closing backtick
```

Because neither strip references the captured content, no path value can defeat it — the loop is guaranteed to shorten `paths_str` by at least the `\`...\`` token each iteration and terminate.

Audit the sibling comma-separated fallback branch (same function): it uses `IFS=','` splitting and `sed` trims, no `${var#glob}` on captured content — expected clean, confirm and leave as-is (FR3).

Lock behavior with a regression case appended to the existing plain-bash suite `plugins/specclaw/tests/run-parser-tests.sh`, following its `make_change` + `VERIFY collect` + `jq` + `assert_eq` conventions, guarded by a `timeout` so a regression manifests as a fail, not a hung CI.

## Architecture

Single-function, single-file behavioral fix inside an existing bash parser. No structural change. Test suite gains one case block. No changes to `/specclaw:verify` skill logic, acceptance-criteria parsing, or output schema.

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-verify` | modify | Replace glob-unsafe strip with two content-agnostic backtick strips in the backtick loop (~L118–122). Confirm fallback branch clean. |
| `plugins/specclaw/tests/run-parser-tests.sh` | modify | Add regression case: `**Files:**` with `app/[id]/page.tsx` (+ a multi-token `[...slug]` variant) → `verify collect` terminates under `timeout` and extracts literal paths. |
| `plugins/specclaw/.claude-plugin/plugin.json` | modify | Patch version bump. |
| `.claude-plugin/marketplace.json` | modify | Patch version bump (keep in sync). |

## Data Model Changes

None.

## API Changes

None. `specclaw-verify collect` output schema (`.changed_files[].path`, `.acceptance_criteria`) unchanged.

## Key Decisions

- **Two-strip over quoting the token** (`${paths_str#*\`"${BASH_REMATCH[1]}"\`}`): both fix the bug, but two content-agnostic strips don't depend on the captured value at all and read more obviously correct. Chosen.
- **Guard the test with `timeout`**: without it a reintroduced infinite loop hangs the whole suite instead of failing the case. Use a small bound (e.g. `timeout 10`).
- **Defer broad audit**: only fix the verify script now; note any sibling occurrences to learnings/patterns for a possible follow-up, per approved scope.

## Risks & Mitigations

- **Risk:** two strips behave differently from one on adjacent/empty tokens (e.g. two backticks with nothing between). **Mitigation:** the regex `\`([^\`]+)\`` requires ≥1 non-backtick char between backticks, so a matched token always has both delimiters present; two strips are exact. Covered by AC-2/AC-4.
- **Risk:** regression to existing extraction. **Mitigation:** NFR2 / AC-3 — full suite must still pass; AC-4 asserts byte-identical output for plain paths.
