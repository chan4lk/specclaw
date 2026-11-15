# Code Review Report: 048-codex-safe-mod-hooks

**Reviewed:** 2026-11-03
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

3 findings: 0 BLOCK, 1 WARN, 2 NOTE

## Findings

### [WARN] plugins/specclaw/tests/run-codex-plugin-tests.sh:78 — Correctness / Test quality
**Problem:** `extra="$(python3 -c '...' "$hooks_file" 2>&1)"` merges stderr into `extra`. An unparsable hooks.json still fails the check (the traceback is non-empty, so `[ -z "$extra" ]` is false), but the message becomes `(found: Traceback ... JSONDecodeError ...)`, a multi-line traceback. The fallback `${extra:-unparsable}` in `fail "... (found: ${extra:-unparsable})"` can never run: if python exits non-zero, `extra` already holds a traceback. I ran a broken file through the python line and confirmed it prints a traceback.
**Fix:** Drop `2>&1`, so the traceback goes to the test's stderr and `extra` stays empty on a crash. Then change the fail text to something like `(found: ${extra:-unparsable or empty})`. Alternatively, use `|| extra=unparsable`.

### [NOTE] plugins/specclaw/tests/run-codex-plugin-tests.sh:77-82 — Correctness
**Problem:** Checked and OK under `set -euo pipefail`. `a && b && pass || fail` is an AND-OR list, so `set -e` does not trigger on the failing left side, and `fail` only sets `failed=1`. Quoting is fine (`"$hooks_file"` is passed as argv). Two small gaps remain. (1) If no `plugins/*/hooks/hooks.json` matches, the glob stays literal, python fails, and the run reports a confusing FAIL. That cannot happen today, because two files exist. (2) Nothing checks that the `"hooks": "./hooks/mod.json"` path in `.claude-plugin/plugin.json` exists. A typo there would silently drop the mod. This is optional hardening.
**Suggestion:** None needed. Optionally add `[ -f "$PLUGIN_DIR/hooks/mod.json" ]`.

### [NOTE] plugins/specclaw/CLAUDE.md:395 — Scope creep
**Problem:** The `run-mod-tests.sh` table row changed "reader" to "change parsing". That is unrelated to the mod relocation and is not in the spec's scope. It is harmless.
**Suggestion:** Revert it, or accept it.

## Other checks

- CI (`.github/workflows/ci.yml`) runs `run-codex-plugin-tests.sh`, so the new check is enforced. Both hooks.json files (specclaw, specclaw-review) pass on a live run.
- A repo-wide grep for `modules`, `mod.json` and `hooks.json` found no other code, CI step or test that assumes the mod lives in hooks/hooks.json. `run-mod-tests.sh` does not reference it.
- Doc accuracy: the plugins/specclaw/CLAUDE.md session-bootstrap paragraph, MOD.md and the `.specclaw/context.md` notes match the change. The CLAUDE.md sentence is inserted mid-paragraph before "It injects", so its pronoun reads awkwardly. That is cosmetic.
- All 10 plugin manifests are bumped consistently to 0.8.7 (R1 satisfied). design.md is absent, so D8 is skipped.

## Verdict Rationale

The fix is correct: hooks.json is reduced to the keys Codex accepts, the mod is moved to a file only the Claude manifest names, and the guard test passes and is wired into CI. The one real defect is cosmetic. The test's error handling for an unparsable file does fail, but with a traceback in the message and a dead fallback string. No blocking issues.
