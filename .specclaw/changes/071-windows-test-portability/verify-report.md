# Verify Report: 071-windows-test-portability

**Verdict:** PARTIAL — AC-5 (Linux/macOS unchanged) could not be run here; every other AC is met
**Head:** f5acb17 (4 task commits on f6d45b4)
**Code Review:** APPROVED_WITH_NOTES — 0 BLOCK, 1 WARN (resolved), 3 NOTE (resolved)
**Review loop:** CLEAN — 5 rounds, final pass opus, 0 blocker / 0 major / 4 minor
**Tested on:** Windows 11, Git Bash only. Linux/macOS not run.

## Acceptance criteria

- **AC-1** met — `bash plugins/specclaw/tests/run-preset-check-tests.sh` on Git Bash: "All preset-check tests passed (4 skipped)." (was 58 failures). 4 symlink checks print SKIP.
- **AC-2** met — check "AC-1b output is LF-only with / separators" passes, non-empty guard added.
- **AC-3** met by construction — `SYM` is set only when a real symlink was made, so the checks still run and can FAIL wherever links work. Not exercised here (no symlinks on this machine); reviewer agreed it is sound.
- **AC-4** met — check "071 AC-4 git helpers decode non-ASCII diff..." passes; fails against unmodified main code, and fails when only the backend-call or only the test-run fix is removed.
- **AC-5** NOT VERIFIED — Linux/macOS output unchanged. Reasoned: `os.sep` is "/" there and cygpath is guarded; no run. CI on the fork is the check.
- **AC-6** met — all 21 version fields are 0.9.17.

## Other suites

- `run-review-tests.sh`: 10 failures, the same 10 (by name) as unmodified main on this machine; the new 071 check passes. Not caused by this change.
- Evidence collector (`specclaw-verify collect`) prints test/lint/build commands as passing (none configured at the project level).

## Follow-ups (minor, not done)

- `git()` uses `errors="replace"` while `find_root` uses `surrogateescape`: pick one policy for path-bearing git output.
- The review test's `Cfg` stub could be a real `rc.Config` built from a temp `.specclaw/config.yaml`.
- `find_root` basename assertion passes without the fix on Linux/macOS (UTF-8 locale); only the 0x8f rows prove anything there.
- `ln -s` for two symlink setups still prints to stderr on Git Bash (noise only).
- `specclaw-presets` stderr still gets CRLF on Windows (only stdout was fixed); `sys.stdout.reconfigure(newline="\n")` on both streams would remove the second rule.
- `specclaw-verify collect` garbles non-ASCII (mojibake) on Windows: separate Windows decode bug.
- 10 pre-existing review-suite failures on Windows.
