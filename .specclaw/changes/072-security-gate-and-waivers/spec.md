# Spec: Prevent known pen-test findings while SpecClaw builds

**Change:** 072-security-gate-and-waivers
**Size:** bounded

## Overview

Builders get the stack security rules. The infosec reviewer runs by default and warns. A project can
make an unwaived BLOCK stop `/specclaw:pr`. A person can waive a finding with a written reason. And
the recurring pen-test findings that have no rule yet get one, plus a practice test.

## Gap check (done at plan time)

Each recurring finding in the sample pen-test reports was compared with `presets/*.md` (`## Security`),
`specclaw-review/review-rules/*.md` and `tests/evals/infosec/`.
- **Already covered:** dev bypass (B16), code in a response (B16), sessions surviving logout (B17),
  sign-in enumeration (B18), uncapped code attempts (B19), substring URL allowlist (B20), node
  `trustProxy` (ND11), secrets (B8), injection into SQL/shell/HTML/paths (B8), weak password hashing
  (B15), redirects in nextjs/react-spa (NX6, RS8).
- **Gaps this change closes:**

| # | Finding pattern (generic) | Preset line | Pack rule |
|---|---|---|---|
| G1 | An ownership or role check that is skipped when the caller's identity is missing, or that tests the *target's* role instead of the caller's | base `Access` (extended) | **B21** |
| G2 | A security control (rate limit, validation, issuer) that turns off or falls back to a default when its setting is missing | base `Config` (new) | **B22** |
| G3 | User input built into an outbound URL (path or query) without encoding | base `Injection` (extended) | **B8** (extended) |
| G4 | A token or credential taken from request data (header, body, tool argument) and used instead of the caller's own identity | base `Identity` (new) | **B23** |
| G5 | A redirect target taken from the request without an allowlist of registered or local targets | base `Redirects` (new) | **B24** |
| G6 | dotnet and python auth routes with no rate limit, or a rate limit keyed on a client-set forwarded header | dotnet/python `RateLimit`, `Proxy` (new) | **DN10, DN11, PY12, PY13** |
| G7 | Resource lookups that answer "not found" vs "forbidden" differently, revealing which ids exist | base `Enumeration` (extended) | **B18** (extended) |

These are left for the learning loop, not this change: CSRF on cookie forms, revocation that does
nothing, non-constant-time secret comparison, token responses without `no-store`, process-local
security state.

## Functional Requirements

- **FR-1** `bin/specclaw-build-context` emits a `## Stack Security Rules` section in every builder
  payload. It holds the `## Security` section of each preset that `specclaw-presets` resolves (base
  first, then the configured stacks, project overrides included), each under the preset's name. If no
  resolved preset has a `## Security` section, no section is emitted and the payload is unchanged.
- **FR-2** `templates/config.yaml` ships `workflow.security_review: true` and a new
  `workflow.security_review_block: false`, with a comment on each. The plan (3c), build (2c) and
  verify (3.52) references run the reviewer unless `workflow.security_review` is explicitly `false`.
  A project whose config has no key gets the review.
- **FR-3** A new script `bin/specclaw-security-gate <specclaw-dir> <change> [--waivers]` reads
  `security-report.md` and `security-waivers.md` in the change folder.
  - **Report heading format:** a finding heading is `### [BLOCK] <path>:<line> — <rule> …`. Any
    heading carrying a BLOCK tag counts (any dash or `:`, an emoji first, or no brackets); one whose
    path or rule cannot be read is unwaived. The gate fails closed.
  - **Waiver line format:** `- Waiver: <path> | <rule> | <accepted risk|false alarm> | <reason>`. The
    reason must not be empty.
  - **When a waiver matches:** a BLOCK is waived when a valid waiver has the same path (ignoring
    `:line`) and its rule matches the first word of the heading's rule field, case-insensitive.
  - **Exit 0:** no unwaived BLOCK. It prints the waived ones.
  - **Exit 1:** one or more unwaived BLOCKs, or a `CHANGES_REQUESTED` verdict with no readable BLOCK.
    It prints each one.
  - **Exit 3:** the report is missing, or it has no single valid verdict line (`APPROVED`,
    `APPROVED_WITH_NOTES`, `CHANGES_REQUESTED` at the start of a line): empty, cut off, `NOT_RUN` or
    conflicting. Did not run never reads as clear.
  - **Exit 2:** usage error.
  - **Invalid waiver lines** (wrong field count, no reason, unknown kind) are printed as invalid and
    never waive anything.
  - **`--waivers`:** prints the valid waivers as a markdown list for the PR body.
- **FR-4** `bin/specclaw-pr` runs the gate before staging, next to the staged-files gate. Its
  behaviour depends on `workflow.security_review_block`:
  - **`true`:** exit 1 or 3 stops the PR with `die`, naming the findings and how to fix or waive them.
  - **otherwise:** it prints a warning and continues.
  - **Review off:** when `workflow.security_review` is `false`, the gate is not run. With the review
    on, a missing or non-executable gate script is a gate failure, never a skipped check.
  - **PR body:** gets a `## Security waivers` section listing the valid waivers. The section is
    omitted when there are none.
- **FR-5** `agents/infosec-reviewer.md` requires the rule field of each finding heading to start with
  the pack rule id or preset keyword it breaks (e.g. `B13`, `Access`), so waivers can match it. The
  verify reference (3.52) runs the gate and appends its one-line result to the verify report.
- **FR-6** The base, dotnet and python presets and packs gain the lines and rules in the gap table
  (G1–G7). Each new preset keyword uses the existing `- **<Keyword>:**` form, and each new pack rule
  the existing `- **<ID> …**` form, with a severity.
- **FR-7** Each new or extended rule has a practice test in `tests/evals/infosec/<case>/`: an invented
  `vulnerable.*`, `fixed.*` and `expect` (`rule: <ID>|<Keyword>`). That is 8 cases: G1–G5, G7 in
  JavaScript, and G6 once in C# and once in Python.
- **FR-8** `tests/run-infosec-evals.sh` gives each sample the rules of its own stack: `.cs` → dotnet,
  `.py` → python, `.js`/`.ts` → node, anything else → base only. Base rules are always included.
- **FR-9** Every new test suite is registered in `.github/workflows/ci.yml`. Every manifest gets one
  patch version bump, and all stay equal (R1).

## Non-Functional Requirements

- **NFR-1** No client names, hosts, emails, secrets or phone numbers from the pen-test reports
  appear anywhere in the repo. Samples are invented.
- **NFR-2** No Shannon prompt text or schema is copied. Rules are written in our own words (AGPL).
- **NFR-3** Scripts decide, models judge. Waiver matching and the PR block are in code, never in
  prose for the model to apply.
- **NFR-4** No GNU-only flags; shellcheck stays clean; scripts use bash or the Python 3 stdlib only.
- **NFR-5** Production diff stays under the 400-line cap (tests excluded). If it won't, split rather
  than waive.

## Acceptance Criteria

- **AC-1** With `presets: [node]`, the builder payload has `## Stack Security Rules` with base and node
  rules. A project override of node replaces the built-in's rules. With no `## Security` sections,
  the payload has no such heading. (test)
- **AC-2** The template has `security_review: true` and `security_review_block: false`. The plan,
  build and verify references treat a missing `security_review` as on. (test; the existing
  "ships false" check is changed to "ships true")
- **AC-3** `specclaw-security-gate` exits 0 with no BLOCK, 0 when every BLOCK is waived, 1 with an
  unwaived BLOCK, and 3 with no report or `NOT_RUN`. A waiver with an empty reason waives nothing and
  is printed as invalid. A waiver for the same rule on another file waives nothing. (test, fixtures
  only)
- **AC-4** `specclaw-pr` with `security_review_block: true` and an unwaived BLOCK stops before
  staging, with a message naming the finding. With `false` it warns and continues. Valid waivers
  appear under `## Security waivers` in the PR body. (test)
- **AC-5** `infosec-reviewer.md` states the rule-field requirement, and verify 3.52 runs the gate.
  (test: required text present, with a deleted-item mutant)
- **AC-6** B21–B24, DN10, DN11, PY12 and PY13 exist. B8 and B18 are extended. Base gains `Config`,
  `Identity` and `Redirects`, and extends `Access`, `Injection` and `Enumeration`. dotnet and python
  gain `RateLimit` and `Proxy`. (structural test via AC-7)
- **AC-7** The 8 new eval cases pass `run-infosec-eval-cases-tests.sh`: each has both samples and
  an `expect` whose id exists in a pack and whose keyword exists in a preset.
- **AC-8** `run-infosec-evals.sh` chooses rules by sample extension (checked by a dry, offline test of
  the rule-selection function; no model call).
- **AC-9** New suites are in `ci.yml`, all existing suites still pass, and every version is equal and
  bumped.

## Edge Cases

- A report with findings but no `## Findings` heading: headings are matched anywhere in the file.
- A waiver line with extra spaces, bold, or `|` inside the reason: fields are trimmed, and the reason
  is everything after the third `|`.
- A path with `:` (Windows drive letter): `:line` is stripped only when it is the last `:` followed by
  digits.
- `security_review` on but the review failed (`NOT_RUN`): blocking projects stop and warn-only
  projects warn. Neither reads it as clear.
- A preset with `## Security` but no rule lines, or no section at all: skipped (an empty heading tells
  the builder nothing).

## Approach

One decision: **block in `specclaw-pr` with a script, the same way `staged_files_block` does**. Verify
stays advisory. A matching waiver lifts the block.

File map:
- `plugins/specclaw/bin/specclaw-build-context`: FR-1
- `plugins/specclaw/bin/specclaw-security-gate` (new): FR-3
- `plugins/specclaw/bin/specclaw-pr`: FR-4
- `plugins/specclaw/templates/config.yaml` and `references/full/{plan,build,verify}.md`: FR-2, FR-5
- `plugins/specclaw/agents/infosec-reviewer.md`: FR-5
- `plugins/specclaw/presets/{base,dotnet,python}.md` and
  `plugins/specclaw-review/review-rules/{base,dotnet,python}.md`: FR-6
- `plugins/specclaw/tests/evals/infosec/*`, `tests/run-infosec-evals.sh`, new and updated `tests/run-*.sh`,
  `.github/workflows/ci.yml`, manifests: FR-7–FR-9
