# Code Review Report: 044-fast-review-loop

**Reviewed:** 2026-10-16
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

11 findings: 0 BLOCK, 6 WARN, 5 NOTE. The offline suite `plugins/specclaw-review/tests/run-review-tests.sh` passes. No `reviews/` directory existed, so there was nothing to de-duplicate against. Evidence is quoted from the changed files.

## Findings

### [WARN] plugins/specclaw-review/lib/review_core.py:235,255 — Security (argument injection through `since`)
**Problem:** `since` reaches git unvalidated, as `f"{since}..HEAD"`, in `changed_files` (line 235) and `diff_text` (line 255). A value that starts with `-` is parsed by git as an option. I confirmed that `git log --no-merges --first-parent --name-only --format= "--output=<path>..HEAD"` creates or overwrites `<path>..HEAD`. `since` comes from the CLI `--since` and from the MCP tool `review_run` / `review_classify` (`args.get("since")`), so an agent-supplied value is an arbitrary-file-write primitive. NFR-5 says inputs are never interpolated unsafely; `--change` is validated by `change_dir`, but `since` is not.
**Fix:** Resolve it first with `git rev-parse --verify --end-of-options <since>^{commit}` and use the resulting SHA, or reject values that start with `-`. Add a test.

### [WARN] plugins/specclaw-review/lib/review_core.py:501-504 — Correctness (fail-open on dropped findings)
**Problem:** `if sev in SEVERITIES and x.get("file"): ... out.append(x)` silently discards any finding whose severity is not one of the three values (for example "critical" or "high") or that lacks `file`. If every finding is dropped, the round is recorded as `clean`. This breaks the spec's own fail-closed rule ("never-clear-on-did-not-run", fail-closed input, AC-4). A non-empty array that yields zero usable findings should not clear a round. The loop at line 491 also returns the first array that parses as a list of dicts, so a prose `[]` ahead of the real array would clear it.
**Fix:** Raise `ReviewError(..., 3)` when the array is non-empty and any element is unusable. Alternatively, map unknown severities to `major` and let calibration decide.

### [WARN] plugins/specclaw-review/lib/review_core.py:646 — Correctness (verdict exits 2 instead of 1)
**Problem:** `later = [... git(cfg.root, "diff", "--name-only", f"{fsha}..HEAD") ...]` uses `check=True`. After a rebase or amend, or in a CI clone that lacks the final-pass commit, git fails and `ReviewError` carries the default code 2. `verdict` and `--check-head` should answer "does not cover HEAD", which is exit 1, not a usage error. This is the common post-rebase case.
**Fix:** Call `git(..., check=False)`. If the output is empty and the SHA does not resolve, set `ok=False` with the note " (final pass commit not in history)".

### [WARN] plugins/specclaw-review/lib/review_core.py:612 — Design adherence (memory counts inflate across rounds)
**Problem:** `mem.put(cfg.mem_dir, [dict(f, lesson=f.get("message")) for f in block], change)` runs on every round. The same open finding re-reported in rounds 2 and 3 bumps `count` each time, so one unresolved finding in a single change reaches `count >= 2`. `learn_candidates` filters on `count >= 2`, so it is proposed as a "recurring lesson" without recurring anywhere. This undermines FR-11.
**Fix:** Bump `count` once per change: skip the bump when the entry's `change` equals the current change, or put only on the final or clean round.

### [WARN] plugins/specclaw-review/hooks/guard-memory:15,17 — Design adherence (hook ignores configured `memory_dir`)
**Problem:** `MARKERS = [m for m in {"review-memory", os.environ.get("SPECCLAW_REVIEW_MEMORY_DIR", "")} if m]`. The hook cannot see `review.memory_dir` from `config.yaml`, and nothing in the plugin sets that env var. Setting `review.memory_dir` therefore leaves the memory file unguarded. The literal marker `review-memory` also denies reads and edits of `.claude/rules/specclaw-review-memory.md` itself, which `init` creates, so users cannot open or adjust the guard rule.
**Fix:** Have the hook read `review.memory_dir` through `review_core.Config`, or document that a custom directory disables the guard. Tighten the marker to `.specclaw/review-memory` plus the configured directory.

### [WARN] plugins/specclaw-review/lib/review_core.py:56-70 vs spec FR-7 — Design adherence (spec drift on default models)
**Problem:** `return models.get(which) or {"round": "sonnet", "final": "opus"}[which]` gives sonnet and opus. FR-7 says the defaults are `haiku` for rounds and `sonnet` for the final pass. `skills/review/SKILL.md:70` documents sonnet/opus as deliberate, with replay evidence, but spec.md and design.md were not updated. This is a justified change with no justification in the spec.
**Fix:** Update FR-7 and the design to sonnet/opus, citing `smoke-replay.md`.

### [NOTE] plugins/specclaw-review/bin/specclaw-review:34-35 — Dead code
**Problem:** `v.add_argument("--pr-line", ...)` and `v.add_argument("--check-head", ...)` are accepted but never read. `verdict` always prints one line and always checks HEAD. The CI snippets pass `--check-head`, which looks like it changes behaviour but does not.
**Suggestion:** Remove both flags and the CI argument, or make them do what FR-6 describes.

### [NOTE] plugins/specclaw-review/lib/review_core.py:682 — One-liner / Naming (parsing its own output)
**Problem:** `lens = [int(s.split(": ")[1].split()[0]) for s in per_change]` re-parses strings that `stats` built a few lines earlier. A change name containing `": "` breaks it.
**Suggestion:** Keep `rounds_by_change = {name: len(rs)}` alongside and take `statistics.median(rounds_by_change.values())`.

### [NOTE] plugins/specclaw-review/mcp/server.py:73 — Correctness (uncaught exception kills the server)
**Problem:** `except (rc.ReviewError, KeyError, ValueError, OSError)` does not cover `TypeError`, for example `"/" in change` when `change` is an integer, or a non-dict JSON line reaching `msg.get`. One bad call terminates the stdio loop.
**Suggestion:** Catch `Exception` in the `tools/call` branch and guard `isinstance(msg, dict)` in `main`.

### [NOTE] plugins/specclaw-review/lib/review_core.py:609 — Correctness (escalation key with empty rule)
**Problem:** `seen.setdefault((f.get("rule"), f["file"]), set())` collapses every finding that has no `rule` in a file into one key. Unrelated rule-less findings in the same file escalate (exit 4) after two rounds.
**Suggestion:** Key on `f["fp"]`, as FR-3 says ("a finding fingerprint").

### [NOTE] plugins/specclaw/references/full/pr.md:49-50 and .github CI snippets — Naming / consistency
**Problem:** The inserted step is numbered `2.` directly above the existing `2. **Run:**`, so the full pr.md has two step 2s. Separately, `ci/*.yml` exits 0 with only a warning when the PR has no round files, so a PR that skips the local review passes CI silently.
**Suggestion:** Renumber as `2b.`, as the lean skill does with `1b.`. State in the CI header that a missing review is a deliberate pass, or exit non-zero.

## Dimension notes

- D8: the implementation matches design.md except for the two items above (memory counting, default models).
- D9: `.gitignore` (`__pycache__/`) and `plugins/specclaw/tests/run-plugin-split-tests.sh` are not named in any task's `Files:` list. Both are minor and plausibly necessary (the plugin runs python).
- D6: `review_core.py` is large (857 lines) and `run_round` is about 55 lines with nesting of 4 inside the `try`. This is acceptable but is the next place to split.
- D7: there are no tests for option-like `since`, severity-dropped findings, a verdict after a rebase, or the guard against a custom memory dir. The four WARNs above are untested for that reason.
- Core edits: `specclaw-pr` and `specclaw-azdo-pr` are guarded by `command -v`, and the output is unchanged when the plugin is absent (AC-16). The `|| true` and `${review_line:+...}` handling is correct under `set -e` and `pipefail`.

## Verdict Rationale

There are no BLOCK-level defects. The core loop is fail-closed on backend failure, calibration is enforced in code, and the core hooks are properly guarded and inert when the plugin is absent. The suite passes. The `since` argument injection, the silent dropping of malformed findings that can yield a false CLEAN, the exit-2 verdict after a rebase, and the memory-count inflation should be fixed before the plugin is relied on in CI. None of them breaks the happy path, so the verdict is APPROVED_WITH_NOTES.

APPROVED_WITH_NOTES
