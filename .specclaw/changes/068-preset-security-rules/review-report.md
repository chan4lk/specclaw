# Code Review Report: 059-preset-security-rules

Two reviews ran on this change: part 1 on the base preset, part 2 on the stack presets.

## Part 1 — base preset


## Summary

3 findings: 0 BLOCK, 0 WARN, 3 NOTE

Notes: design.md absent, skipping D8. D9: every changed file is in a `Files:` list in tasks.md (the version bump covers all `plugin.json` and `marketplace.json` files; `.agents/plugins/marketplace.json` has no version field and is correctly untouched). No per-task reviews exist, so nothing is repeated.

## Findings

### [NOTE] plugins/specclaw/presets/base.md:25 — Correctness / clarity
**Problem:** `- **Crypto:** platform libraries only. No home-made crypto, no MD5 or SHA-1 for passwords.` "Platform libraries" is ambiguous (OS or runtime built-ins versus vetted libraries). The password clause only says what to avoid. It does not say what to use, so an agent can swap MD5 for plain SHA-256 and still pass a reviewer reading literally.
**Suggestion:** `- **Crypto:** vetted libraries only. No home-made crypto. Hash passwords with a slow salted password hash, never a plain digest (MD5, SHA-1, SHA-256).` This stays stack-agnostic.

### [NOTE] plugins/specclaw/presets/base.md:24 — Checkability (FR-2)
**Problem:** `- **Dependencies:** no new dependency without a reason.` A reviewer cannot check "a reason" against code. Only "Commit the lockfile" is checkable.
**Suggestion:** `- **Dependencies:** a new dependency needs a one-line reason in the PR/commit message. Commit the lockfile.`

### [NOTE] plugins/specclaw/tests/run-preset-check-tests.sh:149 — Test quality
**Problem:** `sed '/^- \*\*Logging:\*\* /d' "$PLUGIN_DIR/presets/base.md" > "$TMP/base-nolog.md"` AC-3 exercises one deleted rule (Logging) plus the shared loop. It does not exercise the `heading` branch or a rule that is last in the section (the `sed` range end at EOF/next `## `). The loop is uniform across keywords, so the risk is low. The test does fail when a rule is removed: `security_missing` is scoped to the Security section, so a same-named bullet elsewhere cannot mask a deletion.
**Suggestion:** Optionally add one more mutant, for example `sed '/^## Security$/d'`, and assert the output starts with ` heading`.

## Verdict Rationale

The eight rules in `plugins/specclaw/presets/base.md:17-25` cover FR-1 and name no stack, framework or library. They are mostly short, imperative and checkable. `base.md` is 33 lines, well inside the 60-line limit. The new test greps the section, not the whole file, and names the missing keyword. It passes on the real file, and its deleted-rule case returns exactly ` Logging`. The version bump is consistent: all 12 manifest files plus the 6 marketplace entries read 0.9.6, satisfying rule R1. I ran `run-preset-check-tests.sh` here: the two new cases pass, and the suite reports 58 failures. The same 58 occur on a clean `main` worktree, so they are an environment issue (Windows) that this change did not introduce. AC-2's "every case passes" is therefore not demonstrable on this machine and should be confirmed on Linux/CI. No BLOCK or WARN findings, only wording and test-coverage notes.

APPROVED_WITH_NOTES

---

## Part 2 — stack presets


## Summary

4 findings: 0 BLOCK, 2 WARN, 2 NOTE

D8 skipped (no design.md; spec Approach used). No per-task reviews existed.

## Findings

### [WARN] plugins/specclaw/tests/run-preset-check-tests.sh:170 — Test quality
**Problem:** `first="$(stack_keys $st | cut -d' ' -f1)"` only ever deletes the first keyword of each stack. AC-3 says "any one required rule deleted". Removing e.g. `Cors`, `Links` or `Html` is never exercised. The loop in `security_missing` would catch it, but that is not proven for the later keys.
**Fix:** Loop over every key in `stack_keys $st` and run the delete-one mutant for each (about 25 cheap checks).

### [WARN] plugins/specclaw/presets/node.md:32 — Correctness / Design
**Problem:** `- **Cors:** list explicit origins; rate-limit auth routes.` mixes two unrelated rules under a CORS keyword. Rate limiting is not CORS, so an agent or reviewer checking "Cors" may miss it. Deleting the rate-limit half would not fail the test, because only the keyword is checked.
**Fix:** Split it into `- **Cors:** list explicit origins.` and `- **RateLimit:** rate-limit auth routes.` (add `RateLimit` to `stack_keys node` and to the spec).

### [NOTE] plugins/specclaw/presets/dotnet.md:31 — Overlap with base.md
**Problem:** `- **Errors:** one exception handler returns `ProblemDetails`; no stack trace outside Development.` partly restates base `Errors:` ("Never send stack traces or internal details to the client"). FR-2 says to repeat nothing. The ProblemDetails and Development-only wording is stack-specific, so the overlap is small. The `Authorization` bullets in dotnet, python and node are the same case: framework mechanisms for base `Access`, with no ownership check.
**Suggestion:** Cut the trailing clause to `- **Errors:** one exception handler returns ProblemDetails.` Optionally mention the per-resource ownership check, which stack Authorization bullets leave to base.

### [NOTE] plugins/specclaw/presets/react-spa.md:29 — Accuracy
**Problem:** `- **Tokens:** no tokens in `localStorage`; use `httpOnly` cookies.` An SPA cannot set `httpOnly` cookies itself, so this only holds with a backend or BFF that sets them. It also silently implies CSRF handling (`sameSite`), which the section does not mention. Technically sound as guidance, but one clause would make it checkable.
**Suggestion:** `...; the server sets them `httpOnly` + `sameSite`.`

## Technical accuracy of the stack rules

Checked against each framework, and all are correct:
- .NET fallback policy / `RequireAuthorization()`, DTO binding against over-posting, `ProblemDetails`, `IHttpClientFactory`, and the `AllowAnyOrigin` + credentials ban (the combination is rejected at runtime).
- Python `extra="forbid"`, `yaml.safe_load`, `httpx` timeout and `verify=False`, and no `shell=True`/`eval`/`pickle`.
- Node Zod `.strict()`, no `exec`/`eval`/`new Function`, and prototype pollution via merging.
- Next.js `server-only`, cookie flags, local-path redirects, CSP in `next.config`, `dangerouslySetInnerHTML`.
- React `VITE_*` shipping to the browser, `javascript:` hrefs, and the open-redirect return path.

Each rule is a short, checkable bullet. The `Html` rule appears in both nextjs and react-spa, which is intended because the presets are separate.

## Test verification

- All new stack checks pass. The Security AC-5 mutants really do fail the helper and report ` <Keyword>`, so the test is not vacuous.
- Presets are 40-43 lines, so the 60-line cap holds.
- The script reports "58 failure(s)", but the same count appears on a clean main worktree. They are pre-existing environment failures (local-dir / `specclaw-presets` checks on this Windows shell), not caused by this change.

## Verdict Rationale

No security or correctness defects were found. The stack rules are accurate, concise and match the spec's keyword lists, and the new test fails when a rule is removed. The WARNs are a test that covers only the first rule per stack and a node `Cors` bullet that bundles rate limiting. Neither blocks the change.
