# Verification Report: 059-preset-security-rules

**Verdict:** PASS

- AC-1: pass — `presets/base.md` has `## Security` with one `- **Keyword:** ` rule each for Secrets, Input, Injection, Access, Errors, Logging, Dependencies, Crypto; test `Security AC-1` passes.
- AC-2: pass — presets are 33–43 lines (limit 60); `AC-10 presets exist ≤60 lines` and every Security check pass. The full suite shows 58 failures on this Windows machine, identical on a clean `main` worktree (`specclaw-presets` prints `C:\...` paths where tests expect POSIX paths); CI runs on Linux.
- AC-3: pass — the `Security AC-3` tests delete one rule, two rules, the heading, and move a rule under `## Tests`; `security_missing` reports each by name.
- AC-4: pass — dotnet, python, node, nextjs and react-spa each have a `## Security` section (before `## Shared`) with a `- **Keyword:** ` bullet for every keyword listed in spec.md for that stack.
- AC-5: pass — for every stack the test deletes each required rule in turn and `security_missing` reports it by exact keyword.

## Tests

```
PASS: Security AC-1 base.md has a Security rule for all eight keywords
PASS: Security AC-3 (four base mutants, each reported by name)
PASS: Security AC-4 <stack> has all its Security rules (five stacks)
PASS: Security AC-5 <stack> with the <keyword> rule deleted is reported by name (26 checks)
```

## Scope

The branch touches the six presets, `tests/run-preset-check-tests.sh`, and the 0.9.5 → 0.9.6 bump in
all twelve plugin manifests and `.claude-plugin/marketplace.json`: the spec's file map, nothing else.
FR-3 (no copies of base.md rules): pass.

**Code Review:** APPROVED_WITH_NOTES — base: 3 findings (0 BLOCK, 0 WARN, 3 NOTE); stack presets: 4 findings (0 BLOCK, 2 WARN, 2 NOTE), all four fixed. See review-report.md.
**specclaw-review:** CLEAN on both parts. Base: 5 rounds, final pass by opus, last round 0/0/2 b/M/m (round 2 was refused by the model as a usage-policy false positive, recorded as not_run, and re-run). Stack presets: 2 rounds, final pass clean. After the code-review fixes (RateLimit split, delete-every-rule test, .NET and React wording) a re-review reported 1 major + 1 minor, both deliberately not acted on: (R1) a second version bump to 0.9.7 — CONTRIBUTING.md step 4 asks for one patch bump per PR and the branch is already 0.9.5 → 0.9.6; (B2) the .NET Errors wording — intentional, recorded in spec.md Edge Cases #2. Minors are in follow-ups.md.
