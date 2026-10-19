# Proposal: macOS test portability

**Created:** 2026-10-20
**Status:** 🟡 Draft

## Problem

Five suites fail on macOS with zero code changes (same counts on `main`): long-orchestration (28),
parser (5), change-numbering (6), phase-state (1), synth-agent (1). CI is Linux-only, so nobody sees
it — but two of the causes are real product bugs on macOS, not just test bugs.

Investigation (one root cause each, each reproduced):

| # | Where | Cause | Failures |
|---|---|---|---|
| 1 | `bin/specclaw-run-long` (2 sites) | BSD `wc -l` pads: marker reads `truncated,      500 total lines` | long AC2 |
| 2 | `bin/specclaw-browser-lock:220` | `systemd-run` probe calls bare `timeout`; absent on macOS → probe fails → MemoryMax cap silently dropped | long AC10–13, edge2, edge13, scoping (~25) |
| 3 | `tests/run-long-orchestration-tests.sh` edge1b | forces `mktemp` failure via `TMPDIR=<file>`; BSD `mktemp -d` ignores `TMPDIR` | long edge1b (2) |
| 4 | `tests/run-parser-tests.sh:445` | bare `timeout 10` → rc 127 | parser (5) |
| 5 | `tests/run-change-numbering-tests.sh:261` | `find -printf` (GNU) → empty names | numbering AC8–11 (5) |
| 6 | phase-state:996, change-numbering:916 | `wc -l` padding compared to `"0"` | Ha (2) |
| 7 | `tests/run-synth-agent-tests.sh:109–119` | `stat -c %Y`, `sed -i` without suffix (GNU) → task never edited | synth (1) |

## Proposed Solution

Smallest portable fix per cause, reusing the repo's existing idiom:
1. `$(( $(wc -l < f) ))` / `tr -d ' '` on the count.
2. Reuse the `timeout → gtimeout → run plain` fallback already in `specclaw-update-status:126`.
3. Make `mktemp` fail with a PATH-shim `mktemp` that exits 1 (platform-independent), instead of `TMPDIR`.
4. Same timeout fallback in the test.
5. `for d in */; do …` (or `ls -1`) instead of `find -printf`.
6. `| tr -d ' '` on the two counts.
7. Portable mtime (`stat -c %Y || stat -f %m`) and `sed -i.bak … && rm`.

## Scope

### In Scope
- The 7 causes above; all five suites green on macOS, still green on Linux CI.

### Out of Scope
- A macOS CI job (worth doing; separate change).
- Sweeping every other suite for GNU-isms not currently failing.
- Making memory caps work on macOS (no systemd there; uncapped + WARN stays the behaviour).

## Impact

- **Size:** bounded (fixes inside existing scripts and tests; no new flow)
- **Files affected:** 7 + version bump
- **Complexity:** small
- **Risk:** low — Linux behaviour unchanged (GNU `wc` has no padding; `timeout` present takes the same path)

## Open Questions

- None.

---

**To proceed:** Review this proposal and approve to begin planning.
