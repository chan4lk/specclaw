# Spec: macOS test portability

**Change:** 046-macos-test-portability
**Size:** bounded

## Functional Requirements

- **FR-1** `specclaw-run-long` prints the truncation marker with an unpadded count on BSD and GNU.
- **FR-2** `specclaw-browser-lock`'s `systemd-run` probe works without `timeout` on PATH (falls back to `gtimeout`, then a plain call), like `specclaw-update-status`'s `with_timeout`.
- **FR-3** The five suites use no GNU-only flags: no `find -printf`, `stat -c`, suffixless `sed -i`, bare `timeout`, or padded `wc -l` comparisons; edge1b forces `mktemp` failure via a PATH shim.

## Acceptance Criteria

- **AC-1** `run-long-orchestration-tests.sh` exits 0 on macOS.
- **AC-2** `run-parser-tests.sh` exits 0 on macOS.
- **AC-3** `run-change-numbering-tests.sh` exits 0 on macOS.
- **AC-4** `run-phase-state-tests.sh` exits 0 on macOS.
- **AC-5** `run-synth-agent-tests.sh` exits 0 on macOS.
- **AC-6** Linux CI stays green (the same suites on the PR's CI run).

## Approach

Fix each root cause at its source, reusing the existing timeout fallback idiom; no new helpers or
shared libs. The existing suites are the tests (AC-1..5 are their exit codes).

File map:
- `plugins/specclaw/bin/specclaw-run-long`
- `plugins/specclaw/bin/specclaw-browser-lock`
- `plugins/specclaw/tests/run-long-orchestration-tests.sh`
- `plugins/specclaw/tests/run-parser-tests.sh`
- `plugins/specclaw/tests/run-change-numbering-tests.sh`
- `plugins/specclaw/tests/run-phase-state-tests.sh`
- `plugins/specclaw/tests/run-synth-agent-tests.sh`
- `plugins/*/.c*-plugin/plugin.json`, `.claude-plugin/marketplace.json` (version bump)
