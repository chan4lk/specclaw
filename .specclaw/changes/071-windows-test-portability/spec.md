# Spec: Windows (Git Bash) test portability

**Change:** 071-windows-test-portability
**Created:** 2026-11-18
**Status:** 🟡 Draft

## Overview

On Windows with Git Bash, `run-preset-check-tests.sh` fails 58 checks and `specclaw-review` crashes,
with zero code changes. Four causes, each reproduced:

1. `specclaw-presets` is run by Windows Python: `print()` writes `\r\n`, and `realpath` returns `C:\…`.
   Two checks and every `sed -E 's|.*/…\.md$|…|'` consumer then fail (`\r` defeats `$`, backslashes defeat `/`).
2. The test builds expected paths with `pwd -P` (`/tmp/…`, `/c/…`), which never equal Python's output.
3. Git Bash `ln -s` silently makes a **copy**, not a symlink, so 4 symlink checks test nothing.
4. `specclaw-review`'s `git` helper decodes output as `cp1252` → `UnicodeDecodeError`.

Probe on a scratch copy: fixes 1+2 take the suite from 58 failures to 4; the remaining 4 are cause 3.

## Requirements

### Functional Requirements

- **FR-1** `specclaw-presets` prints one path per line, `\n`-terminated, with `/` separators, on every OS.
- **FR-2** The preset test normalises its expected paths with `cygpath -m` when `cygpath` exists.
- **FR-3** Symlink checks run only when `ln -s` makes a real link; otherwise print `SKIP:` and do not fail.
- **FR-4** `specclaw-review` reads and writes text as UTF-8 (`errors="replace"`) in its git helpers, the model-backend call and the test-command call.

### Non-Functional Requirements

- **NFR-1** No behaviour change on Linux/macOS: output bytes identical there (paths already use `/`).
- **NFR-2** No new dependency; no change to other tests.

## Acceptance Criteria

- **AC-1** On Git Bash, `bash plugins/specclaw/tests/run-preset-check-tests.sh` reports 0 failures
  (4 symlink checks may print `SKIP:`, never `FAIL:`).
- **AC-2** `specclaw-presets <project>` output has no `\r` and no backslash (test asserts it).
- **AC-3** The symlink checks still `FAIL` when a real symlink is created and the script wrongly accepts it
  (the `SKIP` guard only fires when `[ -L ]` is false).
- **AC-4** On Git Bash, `specclaw-review run` no longer raises `UnicodeDecodeError` on a diff containing
  non-ASCII bytes.
- **AC-5** On Linux/macOS the preset suite output and pass count are unchanged (CI green).
- **AC-6** Plugin versions are bumped (R1).

## Approach

One decision: fix at the source (the script's output) where a Windows user also benefits, and only
normalise in the test what the OS genuinely differs on (the expected path style).

File map:
- `plugins/specclaw/bin/specclaw-presets` — write `\n`, `/` separators (FR-1).
- `plugins/specclaw/tests/run-preset-check-tests.sh` — `cygpath -m` on `P` and `L`, symlink guard, AC-2 check (FR-2, FR-3).
- `plugins/specclaw-review/lib/review_core.py` — `encoding="utf-8", errors="replace"` in the `git` helper(s) (FR-4).
- `plugins/*/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — version bump.

## Edge Cases

- Linux/macOS: `cygpath` absent → guarded by `command -v`; `chr(92)` replace is a no-op on POSIX paths.
- A POSIX path that legitimately contains a backslash would be rewritten; accepted, preset paths never do.
- Windows users who do enable real symlinks (`MSYS=winsymlinks:nativestrict`) run the symlink checks for real.
