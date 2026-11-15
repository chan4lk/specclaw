# Code Review Report: 063-dash-launch-approve-caps

**Reviewed:** 2026-11-14
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

5 findings: 0 BLOCK, 2 WARN, 3 NOTE

design.md absent (bounded change), skipping D8. D9: all changed files are in the tasks.md `files:` lists.

Consent, injection and config-write checks all pass (see Verdict Rationale).

## Findings

### [WARN] plugins/specclaw-dash/hooks/register.tsx:~25 — Correctness (double launch)
**Problem:** `launch` reads `plan`, then runs `act(... commands.launch(plan.launchable), () => ({ selected: [], plan: null }))`. The plan is cleared only after the command returns, and the Bash call can take up to 600 s (`timeout: 600000` in act.ts). A second press of "Confirm" in that window passes the same guard (`plan.launchable.length === 0 || plan.items.join(' ') !== selected.join(' ')`) and runs `optin` plus `trigger` twice. Each `trigger` spends the user's plan.
**Fix:** Clear the plan before running: `await updateActions($, s => ({ ...s, plan: null }))` before the `act` call, or move that clear into the guard.

### [WARN] .claude-plugin/marketplace.json, plugins/*/.claude-plugin/plugin.json — Version rule
**Problem:** All plugins are still at `"version": "0.9.10"`, which `main` already has. The descriptions changed and the behaviour changed, but no `chore: bump version` commit is in the diff. CLAUDE.md requires a bump on every PR, and rule R1 requires all plugins to stay equal.
**Fix:** Bump every plugin and marketplace entry to 0.9.11 in a separate commit before the PR.

### [NOTE] plugins/specclaw-dash/hooks/register.tsx:~15 — Simplicity (mutation inside a `then` callback)
**Problem:** `dryRun` does `ran.out = \`${ran.out}\nFleet could not run. ...\`` inside the `then` callback. It works because `act` records the same `ran` object as `last`. It is a hidden side effect and easy to break.
**Suggestion:** Let `hint` or `dryRunResult` produce the extra line, or have `then` return `last` explicitly.

### [NOTE] plugins/specclaw-dash/hooks/core/actions.ts:6 — Correctness (pattern mismatch)
**Problem:** `PATTERNS.feature` is `/^[a-z]+$/`, which matches today's plugin features (review, fleet, sync, bf, extras, dash). The `**Feature:**` module value is parsed as `\S+` in `loops.ts`. A module such as `Foo.bar` shows up as a toggle, and the refusal appears only after the Dry run press.
**Suggestion:** Filter `launchItems` through the same pattern so an unlaunchable module is never offered.

### [NOTE] plugins/specclaw-dash/hooks/act.ts — Naming/Simplicity
**Problem:** `act(..., quiet = false)` uses a positional boolean, and call sites pass `true` as the fourth argument (`act($, () => commands.caps(dir), ..., true)`), which reads opaquely.
**Suggestion:** Replace with a named option, or name the two list loaders' intent in a comment.

## Verdict Rationale

The hard requirements hold.

- **Consent.** Launch can only act on `plan.launchable`. That list is derived by `dryRunResult` from lines matching `^(would |already opted in by )` for the exact item. `refused:`, error lines, and items with no line never match. `optin` runs first and the `&&` chain halts on any non-zero exit. `optin` and `trigger` re-check ownership in the fleet CLI. Confirm is absent when the selection changed (`plan.items` compared with `selected`), when nothing is launchable, and after a denied or 127 dry run.
- **Injection.** Every interpolated value passes a strict pattern or `quote()`. Change names are `^\d{3}-[a-z0-9][a-z0-9-]*$`, modules and roles `^[a-z][a-z0-9_-]*$`, fingerprints hex, caps `\d{1,9}`, features `[a-z]+`. None can start with `-`. The paths (`cwd`, `.specclaw`) go through `quote()`. The kit test covers `9e4; rm -rf ~`.
- **Config.** The pane writes no config. `$.fs` is read-only, and the `.specclaw/config.yaml` edit happens only through `specclaw-budget` and `specclaw-suggest`.
- **Other.** The CLI additions (`learn --reject`, `--dismissed`, `--undismiss`) are small and tested, and the reject path keeps lessons in memory. Exit-code wrapping is sound: it uses `lastIndexOf`, and an unknown code is shown as -1.

The only substantive defect is the double-press race in Confirm, plus the missing version bump. Neither blocks, but both should be fixed before the PR.

I did not run the test suites and did not verify the 065 `specclaw-budget` JSON contract against a real binary.
