# Verification Report: 068-preset-security-rules

**Verdict:** PASS

- AC-1: pass — `presets/base.md` has `## Security` with one `- **Keyword:** ` rule each for Secrets, Input, Injection, Access, Errors, Logging, Dependencies, Crypto; test `Security AC-1` passes.
- AC-2: pass — presets are 33–43 lines (limit 60); `AC-10 presets exist ≤60 lines` and every Security check pass. The full suite shows 58 failures on this Windows machine, identical on a clean `main` worktree (`specclaw-presets` prints `C:\...` paths where tests expect POSIX paths); CI runs on Linux.
- AC-3: pass — the `Security AC-3` tests delete one rule, two rules, the heading, and move a rule under `## Tests`; `security_missing` reports each by name.
- AC-4: pass — dotnet, python, node, nextjs and react-spa each have a `## Security` section (before `## Shared`) with a `- **Keyword:** ` bullet for every keyword listed in spec.md for that stack.
- AC-5: pass — for every stack the test deletes each required rule in turn and `security_missing` reports it by exact keyword.
- AC-6: pass — each of the six `specclaw-review` rule packs has every security rule listed in spec.md (base B13–B15, DN7–DN9, PY8–PY11, ND6–ND10, NX5–NX8, RS7–RS10), 23 rules, no duplicate ids; test `Security AC-6` passes per pack.
- AC-7: pass — the test deletes each of the 23 rules in turn and reports it by exact id (`Security AC-7`). The review suite has 4 failures (AC-1, AC-19, AC-21, AC-22) on this Windows machine, identical on a clean HEAD.

- T7/T8 (auth-flow and URL rules from a pen test): pass — `base.md` has Sessions, Enumeration, Codes, DevFlags and Urls (38 lines), `node.md` has Proxy (42 lines), and the review packs have B16–B20 and ND11; each has a presence check and a deleted-rule mutant.

## Tests

```
PASS: Security AC-1 base.md has a Security rule for all eight keywords
PASS: Security AC-3 (four base mutants, each reported by name)
PASS: Security AC-4 <stack> has all its Security rules (five stacks)
PASS: Security AC-5 <stack> with the <keyword> rule deleted is reported by name (27 checks)
PASS: Security AC-6 review pack <pack> has all its security rules (6 checks)
PASS: Security AC-7 pack <pack> with <id> deleted is reported by id (29 checks)
```

## Scope

The branch touches the six presets, the six `specclaw-review` rule packs, `tests/run-preset-check-tests.sh`, `specclaw-review/tests/run-review-tests.sh`, and the 0.9.16 → 0.9.17 bump in
all plugin manifests and `.claude-plugin/marketplace.json`: the spec's file map, nothing else.
FR-3 (no copies of base.md rules): pass.

**Code Review:** APPROVED_WITH_NOTES — base: 3 findings (0 BLOCK, 0 WARN, 3 NOTE); stack presets: 4 findings (0 BLOCK, 2 WARN, 2 NOTE), all four fixed. See review-report.md.
**specclaw-review:** CLEAN on both parts. Base: 5 rounds, final pass by opus, last round 0/0/2 b/M/m (round 2 was refused by the model as a usage-policy false positive, recorded as not_run, and re-run). Stack presets: 2 rounds, final pass clean. After the code-review fixes (RateLimit split, delete-every-rule test, .NET and React wording) a re-review reported 1 major + 1 minor, both deliberately not acted on: (R1) a second version bump to 0.9.18 — CONTRIBUTING.md step 4 asks for one patch bump per PR and the branch is already 0.9.16 → 0.9.17; (B2) the .NET Errors wording — intentional, recorded in spec.md Edge Cases #2. Review packs (T5, T6): round 9 on the new commits reported 1 major (R1, no version bump), because that round saw only the new commits and not the 0.9.6 bump already on the branch; the final pass over the whole change (round 10, opus) is CLEAN, 0/0/1 b/M/m. The minor (preset rules without an exact review-pack twin) is covered by the existing ND3, PY4 and RS4 and is left in follow-ups.md. Minors are in follow-ups.md.

**specclaw-review (T7, T8):** CLEAN — round 12 (final, opus) over the whole change, 0/0/4 b/M/m. Round 11 on the two new commits alone reported the version bump (R1) because it could not see the bump already on the branch. The four minors (preset and review-pack wording that disagrees for react-spa Tokens and Links and node Cors, and GNU-only sed in two mutants) are in follow-ups.md.
