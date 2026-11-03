# Code Review Report: 047-specclaw-mod

## Prior review (59d4bc3)

**Verdict:** APPROVED_WITH_NOTES (6 findings: 0 BLOCK, 3 WARN, 3 NOTE). Not repeated here. Verified PASS at 59d4bc3 after 18 rounds.

## Amendment review (59d4bc3..HEAD)

**Reviewed:** 2026-11-03
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

4 findings: 0 BLOCK, 2 WARN, 2 NOTE

Checked: the rename is pure `git mv` plus the listed edits. No `specclaw-mod` reference remains outside `.specclaw/` history. Warn default is consistent across `plugin.json`, `register.tsx` (`options.gate ?? 'warn'`), `MOD.md` and `README.md`. Block semantics in the docs match `gate.ts`. Ran: run-codex-plugin-tests, run-bootstrap-hook-tests (44/0), run-plugin-split-tests, run-lint-meta-tests, run-preset-check-tests. All pass. `bun` and `claude` tests and `tsc` not run.

## Findings

### [WARN] .claude-plugin/marketplace.json:61-64 — Design adherence (double mod for existing users)
**Problem:** The `specclaw-mod` entry was deleted (`-      "name": "specclaw-mod"`) and nothing tells existing users to uninstall it. A user with `specclaw-mod` installed plus an updated `specclaw` gets two mods. Both register the `specclaw-pane` command (one fails, and `register.tsx` then toasts "could not be registered"). Both paint a band and a status entry. Both gate edits; the old one still defaults to `block` and has its own `gate` config. Neither `MOD.md` nor `README.md` mentions migration. The old atom key (`specclaw-mod.snapshot`) differs from the new one (`specclaw.snapshot`), so state does not collide, but the UI duplicates.
**Fix:** Add one line to `plugins/specclaw/MOD.md` Install and to the README: "If you installed `specclaw-mod`, run `/plugin uninstall specclaw-mod@chan4lk`." Optionally have the SessionStart hook or the mod detect it.

### [WARN] plugins/specclaw/hooks/hooks.json:15-17 — Correctness (unverified older-client behaviour)
**Problem:** `"modules": ["./register.tsx"]` now lives in the file that also carries the SessionStart hook that every specclaw user depends on. `MOD.md` asserts "Older versions skip the mod and run the rest of specclaw as usual." Nothing in the diff or tests checks that a Claude Code older than 2.1.287 (or a Codex-adjacent loader) tolerates an unknown top-level `modules` key without rejecting the whole hooks file. Before the amendment a failure cost only the optional add-on. Now it could silently disable the router. Also `plugin.json` now carries `types` and `userConfig`, new to the core plugin.
**Fix:** Confirm on an old client, or soften the `MOD.md` claim to match what was tested.

### [NOTE] plugins/specclaw/.claude-plugin/plugin.json:3 — Version bump
**Problem:** Plugin code and manifest changed but all plugins stay at `0.8.5`. `CLAUDE.md` and rule R1 require a patch bump of every `plugin.json`, `.codex-plugin/plugin.json` and marketplace entry before the PR.
**Suggestion:** Add the `chore: bump version to 0.8.6` commit before opening the PR.

### [NOTE] plugins/specclaw/.claude-plugin/plugin.json:21-29 — Codex plugin / userConfig
**Problem:** Codex is not affected functionally. `.codex-plugin/plugin.json` still ships `./skills/` only, and `run-codex-plugin-tests` passes. The new files (`hooks/*.ts`, `tests/*.ts`, `MOD.md`, `tsconfig.json`, `types/`) sit in the plugin directory but are not referenced by the Codex manifest. Two small points. CI now asserts `claude == codex`, which holds. The `gate` option exists only in the Claude manifest, which is correct. The quoted SessionStart command (`"\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start\""`) is safe: `run-bootstrap-hook-tests` T12 still passes and it handles a plugin root with spaces. On Windows it matches the quoting already used by `specclaw-review` (`python3 \"${CLAUDE_PLUGIN_ROOT}/...\"`), but the script still has no interpreter prefix, which is unchanged.
**Suggestion:** None required.

## Verdict Rationale

The amendment is a faithful move. Old-path references are gone, the warn default is applied consistently in the manifest, the fallback, the tests (hold tests pin `gate: 'block'`, one new default-warn test) and the docs. Existing test suites and the Codex package checks pass. No BLOCK findings. Two WARNs remain: users who keep the old `specclaw-mod` installed will see two mods with no migration note, and the claim that older Claude Code ignores the new `modules` key beside the core SessionStart hook is untested. The version bump is still owed before the PR.
