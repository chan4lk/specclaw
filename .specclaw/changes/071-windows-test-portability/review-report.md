# Code Review Report: 071-windows-test-portability

**Reviewed:** 2026-11-18
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

4 findings: 0 BLOCK, 1 WARN, 3 NOTE

D8 skipped: design.md absent. D9: all 18 changed files are in the `Files:` lists of T1-T4 (change folder untracked, expected). No `reviews/` dir exists, so no prior findings to dedupe.

## Findings

### [WARN] plugins/specclaw-review/lib/review_core.py:532 — Correctness (AC-4 only partly met)
**Problem:** T3 fixes the two git helpers (lines 203, 210) but leaves other `text=True` subprocess calls on the Windows locale codec: `r = subprocess.run(argv, input=prompt, capture_output=True, text=True, cwd=cfg.root,` (line 532, the model backend) and line 713 (`review_test_command`). The prompt carries the diff, so a diff with characters outside cp1252 (CJK, emoji) raises `UnicodeEncodeError` on stdin encoding. The `except (OSError, subprocess.TimeoutExpired)` on line 534 does not catch it, so `specclaw-review run` can still crash on a non-ASCII diff. AC-4 says it "no longer raises" on non-ASCII input. Line 713 swallows decode errors into the misleading "did not start" message (`UnicodeDecodeError` is a `ValueError`). I did not reproduce this; it is standard CPython text-mode behaviour.
**Fix:** Add `encoding="utf-8", errors="replace"` to the calls on lines 532 and 713, or narrow AC-4 to "git helpers" and record the backend path as a follow-up.

### [NOTE] plugins/specclaw/bin/specclaw-presets:145 — Correctness / NFR-1
**Problem:** `.replace(chr(92), "/")` rewrites a backslash on POSIX too. A Linux/macOS project dir containing a literal `\` would get a wrong path, so NFR-1 ("bytes identical on Linux") holds only for ordinary paths. The spec accepts this.
**Suggestion:** `.replace(os.sep, "/")` is a no-op on POSIX and still fixes Windows. Same length, and it removes the NFR-1 caveat. `chr(10)`/`chr(92)` also read oddly; `"\n"` and `os.sep` would be clearer.

### [NOTE] plugins/specclaw/tests/run-preset-check-tests.sh:49 — Test quality
**Problem:** AC-1b compares `wc -c` of the output with and without `tr -d "\r\\"`. If `specclaw-presets` printed nothing (a crash), both counts are 0 and it passes vacuously. AC-1 on the line before already asserts the exact output, so the gap is covered, but AC-1b does not stand alone.
**Suggestion:** Add `[ -n "$(... )" ] &&` to the condition, or accept as is.

### [NOTE] plugins/specclaw/tests/run-preset-check-tests.sh:127 — Test quality (symlink SKIP guard)
**Problem:** None blocking. The probe (`ln -s ... && [ -L "$TMP/lnk" ]`) sets `SYM=1` wherever `ln -s` makes a real link, which includes Linux, macOS and Git Bash with `MSYS=winsymlinks:nativestrict`. All four checks then run through plain `check`, so AC-3 holds and Linux/macOS behaviour is unchanged. The guard can hide a failure only if `$TMP` is on a filesystem without symlinks, where SKIP is the correct outcome. The `2>/dev/null` added to the dangling `ln -s` (line ~137) cannot mask a failure on Linux: if `ln` failed, no `dotnet.md` exists and the built-in fallback output would fail the check. The directory case still uses `check`. SKIP lines are printed but not counted, so the pass count is unchanged.
**Suggestion:** No change needed.

## Focus answers

1. **specclaw-presets output change.** Callers are `skills/build/SKILL.md:10` (an agent reads the printed files), `templates/presets-README.md` (docs) and the preset test; no script parses the output. On Linux/macOS output is byte-identical except for the backslash edge case above. `sys.stdout.buffer.write` is flushed at `sys.exit`, and warnings go to stderr, so ordering is not an issue. `.encode()` is UTF-8; this is better than the old console codec on Windows. `C:/...` paths are accepted by Windows tools. Dedupe (`path not in out`) runs before the replace, which is harmless.
2. **schk guard:** sound, see the NOTE above.
3. **utf-8 decode in git helpers:** correct and minimal for those two helpers. `errors="replace"` only affects bytes that were failing before. The other call sites are not covered, see the WARN.
4. **Version bump (R1):** complete. All 7 `plugin.json` under `.claude-plugin`, all 7 under `.codex-plugin`, and all 7 marketplace entries are 0.9.17. A grep for `0.9.1x` finds no stale 0.9.16 outside `changes/`.

## Verification run

`bash plugins/specclaw/tests/run-preset-check-tests.sh` on Git Bash (Windows): exit 0, "All preset-check tests passed.", 4 `SKIP:` lines, no `FAIL:`.

## Verdict Rationale

No security or correctness defect in the changed lines, and the stated ACs for the preset script, test and version bump hold. The one WARN is that the UTF-8 fix does not reach the backend subprocess that receives the diff, so AC-4's "run no longer crashes" claim may not hold for non-cp1252 characters. The rest are optional hardening.

**Not checked:** Linux/macOS runs (CI only), `specclaw-review run` end to end on Windows, a non-ASCII diff through the backend path, `MSYS=winsymlinks:nativestrict` behaviour.

VERDICT: APPROVED_WITH_NOTES (BLOCK 0, WARN 1, NOTE 3)

## Resolution (after this report)

- WARN (AC-4 only partly met, lines 532/713): fixed. `call_backend` and `_run_tests` now decode UTF-8, and the review suite has a check that fails without each fix.
- NOTE `chr(92)` replace: fixed, now `os.sep`.
- NOTE AC-1b vacuous pass: fixed, asserts non-empty output.
- `schk` symlink guard: reviewer found it sound; skips are now counted in the closing line.
- Local review loop: 5 rounds, final pass CLEAN (0 blocker, 0 major, 4 minor) — minors recorded in verify-report.md as follow-ups.
