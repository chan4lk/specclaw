# Tasks: Prevent known pen-test findings while SpecClaw builds

**Change:** 072-security-gate-and-waivers
**Created:** 2026-11-20
**Total Tasks:** 7

## Summary

Give builders the stack security rules. Turn the reviewer on (warn-only) with a project switch to
block. Add a waiver gate checked in code. Close the 7 rule gaps with practice tests. Then register the
suites and bump the version.

## Tasks

### Wave 1 — Independent pieces

- [x] `T1` — Builders get the stack security rules (AC-1)
  - Files: plugins/specclaw/bin/specclaw-build-context, plugins/specclaw/tests/run-build-context-security-tests.sh
  - Estimate: small
  - Kind: impl
  - Notes: resolve presets with `specclaw-presets`, take each file's `## Security` section, emit
    `## Stack Security Rules` next to the guardrails. No section emitted when nothing qualifies.
    Test: node, project override, and no-section cases.

- [x] `T2` — Reviewer on by default, plus the block switch (AC-2)
  - Files: plugins/specclaw/templates/config.yaml, plugins/specclaw/references/full/plan.md, plugins/specclaw/references/full/build.md, plugins/specclaw/references/full/verify.md, plugins/specclaw/tests/run-infosec-reviewer-tests.sh
  - Estimate: small
  - Kind: config
  - Notes: `security_review: true`, a new `security_review_block: false` with comments (warn-only for
    one release, then a later change flips it). References 3c/2c/3.52 run the review unless the key is
    explicitly `false`. Update the "ships false" check to "ships true" and add a check for the new key.

- [x] `T3` — The waiver gate script (AC-3)
  - Files: plugins/specclaw/bin/specclaw-security-gate, plugins/specclaw/tests/run-security-gate-tests.sh
  - Estimate: medium
  - Kind: impl
  - Notes: Python 3 stdlib. Exit codes 0/1/2/3 as in FR-3; `--waivers` prints the valid waivers as a
    markdown list. Fixture-only tests, including the empty-reason waiver, the same rule on another file,
    a Windows drive-letter path, and `NOT_RUN`.

- [x] `T5` — Rules for gaps G1–G7 (AC-6)
  - Files: plugins/specclaw/presets/base.md, plugins/specclaw/presets/dotnet.md, plugins/specclaw/presets/python.md, plugins/specclaw-review/review-rules/base.md, plugins/specclaw-review/review-rules/dotnet.md, plugins/specclaw-review/review-rules/python.md
  - Estimate: small
  - Kind: docs
  - Notes: follow the spec's gap table. Write rules in our own words; no client data, no Shannon text.
    Keep each preset line one sentence.

### Wave 2 — Wiring and practice tests

- [x] `T4` — `specclaw-pr` blocks on unwaived findings and lists waivers; agent rule field; verify runs the gate (AC-4, AC-5)
  - Files: plugins/specclaw/bin/specclaw-pr, plugins/specclaw/agents/infosec-reviewer.md, plugins/specclaw/references/full/verify.md, plugins/specclaw/tests/run-headless-pr-tests.sh, plugins/specclaw/tests/run-infosec-reviewer-tests.sh
  - Estimate: medium
  - Kind: impl
  - Depends: T2, T3
  - Notes: run the gate beside the staged-files gate, before staging. `security_review_block: true`
    makes exit 1 or 3 a `die`; otherwise warn. Add `## Security waivers` to the body when any exist.
    Skip the gate when `security_review` is `false`. Extend the headless PR suite (block, warn,
    waiver listed). Add a required-text check (with mutant) for the agent's rule-field line and the
    verify gate line.

- [x] `T6` — Practice tests for the new rules and a stack-aware runner (AC-7, AC-8)
  - Files: plugins/specclaw/tests/evals/infosec/fail-open-ownership, plugins/specclaw/tests/evals/infosec/config-fallback, plugins/specclaw/tests/evals/infosec/url-param-injection, plugins/specclaw/tests/evals/infosec/token-from-request, plugins/specclaw/tests/evals/infosec/open-redirect, plugins/specclaw/tests/evals/infosec/resource-enumeration, plugins/specclaw/tests/evals/infosec/dotnet-forwarded-rate-limit, plugins/specclaw/tests/evals/infosec/python-forwarded-rate-limit, plugins/specclaw/tests/run-infosec-evals.sh, plugins/specclaw/tests/run-infosec-eval-cases-tests.sh
  - Estimate: medium
  - Kind: test
  - Depends: T5
  - Notes: invented samples only. `expect` uses `rule: <ID>|<Keyword>` from T5. The runner picks
    rules by extension (`.cs` → dotnet, `.py` → python, `.js`/`.ts` → node, else base), always adding
    base. Add an offline check of the selection function.

### Wave 3 — Release

- [x] `T7` — Register new suites in CI; bump every version (AC-9)
  - Files: .github/workflows/ci.yml, plugins/*/.claude-plugin/plugin.json, plugins/*/.codex-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Kind: config
  - Depends: T1, T3, T4, T6
  - Notes: add `run-build-context-security-tests.sh` and `run-security-gate-tests.sh` to `ci.yml`. One
    patch bump, all versions equal, in its own `chore: bump version to X.Y.Z` commit. Branch
    `specclaw/windows-test-portability` already took 0.9.18, so pick the next free patch at PR time.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
