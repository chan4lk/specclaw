# Verify Report: 048-codex-safe-mod-hooks

**Verdict:** PASS
**Head:** 8a273ba
**Date:** 2026-11-03

## Acceptance Criteria

- AC-1: pass. `hooks/hooks.json` has only `hooks` at the top level, and the SessionStart command is unchanged (`run-bootstrap-hook-tests.sh` 44/44).
- AC-2: pass. `claude plugin validate plugins/specclaw` passes and reads `hooks/mod.json`, listing the `./register.tsx` hooks. `run-mod-tests.sh`: 16 bun + 62 kit tests, ALL PASS.
- AC-3: pass. `run-codex-plugin-tests.sh` passes. Mutation checks: with `modules` put back, a top-level array, an unparsable file, or broken `mod.json` wiring, it fails with a named message each time.
- AC-4: pass. In a Codex session with this `hooks.json` swapped into the installed 0.8.6 cache, there was no `failed to parse plugin hooks config` line and the SessionStart hooks ran. The cache file was restored.
- AC-5: pass. Claude Code 2.1.250 loads the plugin with 9 skills, and the router runs. The mods rollout flag was refreshed afterwards.
- AC-6: pass. `MOD.md`, `plugins/specclaw/CLAUDE.md` and `.specclaw/context.md` name `hooks/mod.json` and the Codex reason.

## Commands

| Command | Exit |
|---|---|
| `bash plugins/specclaw/tests/run-codex-plugin-tests.sh` | 0 |
| `bash plugins/specclaw/tests/run-mod-tests.sh` | 0 |
| `bash plugins/specclaw/tests/run-bootstrap-hook-tests.sh` | 0 |
| `bash plugins/specclaw/tests/run-plugin-split-tests.sh` | 0 |
| `bash plugins/specclaw/tests/run-codex-skill-tests.sh` | 0 |
| `specclaw-quality-scan . --gate` | 0 |
| `specclaw-preset-check .` | 1: pre-existing violations only, none in `plugins/specclaw` |
| `specclaw-review verdict --change 048-codex-safe-mod-hooks` | 0 |

## Review

**Review:** CLEAN. 4 rounds, final pass 8a273ba (sonnet/opus). The open minors are in `follow-ups.md`.
**Code Review:** APPROVED_WITH_NOTES: 0 BLOCK, 1 WARN, 2 NOTE. The WARN was fixed: an unparsable `hooks.json` now reports `unparsable` instead of a traceback.
