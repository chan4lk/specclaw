# Code Review Report: 046-macos-test-portability

**Reviewed:** 2026-10-20
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

3 findings: 0 BLOCK, 0 WARN, 3 NOTE

design.md absent — skipping D8. No per-task reviews existed.

## Findings

### [NOTE] plugins/specclaw/bin/specclaw-browser-lock:216 and plugins/specclaw/tests/run-parser-tests.sh:445 — One-liner / duplication
**Problem:** The same three-branch timeout fallback is written twice more (`bounded5`, `bounded10`) and a third time already exists in specclaw-update-status. Quoted: `else perl -e 'alarm shift; exec @ARGV' 5 "$@"; fi`. Acceptable for a bounded change, but a perl-alarm timeout exits 142 rather than 124. Both call sites only test for success or failure, so nothing breaks.
**Suggestion:** None required. If a fourth copy appears, share one helper.

### [NOTE] plugins/specclaw/bin/specclaw-run-long:197,332 — Correctness (Linux preservation checked)
**Problem:** `wc -l < "$log_file" 2>/dev/null | tr -d ' ' || echo 0`. The pipe changes which command's exit status the `||` sees. This is safe because line 10 sets `set -euo pipefail`, so a failing `wc` still falls through to `echo 0`. On Linux `wc` output has no padding, so `tr` is a no-op. No defect; recorded so the `pipefail` dependency is explicit.

### [NOTE] plugins/specclaw/tests/run-synth-agent-tests.sh:106 — Correctness edge
**Problem:** `mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }`. On Linux, if the file is missing, `stat -f %m` runs against the filesystem and prints a bogus value instead of failing. Only reachable when the code under test is already broken, since the cache case would then fail on the other assertions too. No action needed.

## Verdict Rationale

The two bin fixes are minimal and preserve Linux behaviour. `tr -d ' '` is a no-op on GNU `wc`. The `timeout`, then `gtimeout`, then `perl` fallback tries `timeout` first, so Linux behaviour is unchanged. The perl `alarm` survives `exec`, so the 5s bound still holds. The test edits are portable equivalents: `sed -i.bak` plus `rm`, `find | sed` in place of `-printf`, `stat -c` then `stat -f`, and `tr -d ' '` on `wc`. The `mktemp` shim in case 16 is scoped to the single invocation, so it also works on Linux and forces the failure that BSD ignores `TMPDIR` for. No security issues: no new input paths, and all args are quoted. Scope matches `tasks.md` T1 and T2. The T3 bump touches ten manifests rather than the two listed, but this matches `plugin.version_files` in `.specclaw/config.yaml`. The 0.8.4 choice (skipping 0.8.3) is explained in the commit message because 045 holds 0.8.3. I did not run the suites on Linux.

APPROVED_WITH_NOTES
