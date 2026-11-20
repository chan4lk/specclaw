# Proposal: Windows (Git Bash) test portability

**Created:** 2026-11-18
**Status:** 🟡 Draft

## Problem

On Windows with Git Bash, `plugins/specclaw/tests/run-preset-check-tests.sh` reports 58 failures
(AC-1..AC-4 and ~54 "045 variant" checks) and `specclaw-review` crashes, with zero code changes
(same counts on `main`). CI is Linux-only and the architect works on macOS/Linux, so nobody sees it —
but our own team is macOS + Windows, and the Claude Code desktop app and VS Code run plugin scripts
through Git Bash on Windows.

Causes found so far:

| # | Where | Cause |
|---|---|---|
| 1 | `run-preset-check-tests.sh` (`P=`, `proj()`, `res()`) | bash `pwd -P` gives `/c/Users/...`; Windows Python in `specclaw-presets` prints `C:\Users\...`, so the string compare never matches |
| 2 | same, via `specclaw-presets` stdout | Windows Python writes `\r\n`; a trailing `\r` breaks every compare |
| 3 | same, lines ~120–130 | `ln -s` fails without Windows symlink rights |
| 4 | `specclaw-review` `git` helper | subprocess output decoded as `cp1252` → `UnicodeDecodeError`, then `impact_set` reads `None` |

Probing causes 1+2 cleared only AC-1..AC-3, so the remaining ~55 checks (AC-4, "045 variant") still
need their cause confirmed in plan.

## Proposed Solution

Smallest fix per cause, no behaviour change on Linux/macOS:
1. Make `specclaw-presets` write `\n` line endings (the script, not each test).
2. In the test, normalise expected paths with `cygpath -u` when `cygpath` exists (no-op elsewhere).
3. Skip symlink checks with a visible "SKIP (no symlinks)" when `ln -s` cannot create a link.
4. Decode git output as UTF-8 in `specclaw-review`.
5. Confirm the cause of the remaining checks, then fix or document.

## Scope

### In Scope
- `plugins/specclaw/bin/specclaw-presets`, `plugins/specclaw/tests/run-preset-check-tests.sh`,
  the `git` helper in `plugins/specclaw-review/lib/review_core.py`.
- Preset test suite green on Git Bash; unchanged green on Linux CI.

### Out of Scope
- macOS BSD `sed` in the security mutants (on hold) and change 046's macOS suites.
- Other Windows failures in the review test suite (7 identical on `main`) unless the same cause.
- PowerShell without Git Bash (scripts are bash by design).
- Opening a PR to the architect's repo (stays on the fork).

## Impact

- **Size:** bounded (alters existing scripts and one test file)
- **Files affected:** 3–4 (estimated)
- **Complexity:** small
- **Risk:** low (Linux/macOS behaviour must not change; CI is the check)

## Open Questions

- Does Windows Python also need `PYTHONUTF8` set inside the scripts, or only the git decode?
- Is `\n` output from `specclaw-presets` acceptable to every other consumer of it?

---

**To proceed:** Review this proposal and approve to begin planning.
