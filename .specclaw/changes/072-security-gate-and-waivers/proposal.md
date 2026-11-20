# Proposal: Prevent known pen-test findings while SpecClaw builds

**Created:** 2026-11-20
**Status:** 🟡 Draft

## Problem

Teams build products with SpecClaw, run a Shannon pen test on them, and then go back to fix what it
finds. This happens on almost every project, and the same kinds of flaws keep coming back:
- a dev bypass left switched on;
- a rate limit keyed on a header the client sets;
- an ownership check that is skipped when the caller has no identity;
- a security setting that quietly turns off when its config value is missing.

Changes 069 and 070 started on this. 069 added `## Security` rules to the stack presets, and 070
added the `infosec-reviewer` agent with practice tests. Three gaps keep them from preventing much:

1. **The builders never see the rules.** In the full flow, builder agents get `context.md` and
   `agent-hints.md` but no presets (`bin/specclaw-build-context`). Only lean build and the reviewer
   read presets. The agents that write the code don't know the lessons.
2. **The reviewer is off and can't block.** `workflow.security_review` ships `false`, and when it
   runs it only gives advice. A flaw it finds still ships, and Shannon finds it later.
3. **Some recurring findings have no rule yet.** 069 covered the authentication findings. The
   recurring authorization, config and outbound-request findings from the reports have no preset
   line, no review-pack rule and no practice test.

## Proposed Solution

Four parts. Each one reuses an existing mechanism.

1. **Builders get the stack security rules.** `specclaw-build-context` adds a `## Stack Security
   Rules` section to every builder payload. It takes the `## Security` section of each preset
   resolved by `specclaw-presets`: base first, then the project's stacks, with project overrides
   included. It sits next to the `security-requirements.md` builders already get. This is the
   cheapest prevention: the rule is in front of the agent before it writes the line.

2. **The reviewer is on by default and warn-only, and a project can make it block.**
   - `workflow.security_review` ships `true`. The agent behaves as today: it warns and never fails
     verify.
   - A new key, `workflow.security_review_block`, ships `false`. When a project sets it to `true`,
     an unwaived `[BLOCK]` finding in `security-report.md` stops `/specclaw:pr`. This is enforced
     in `bin/specclaw-pr`, the same way `staged_files_block` is today.
   - BISTEC projects set the key to `true` and are blocked from day one.
   - Making blocking the default for everyone is a later change, once this one has shown it isn't
     noisy. That follows upstream's habit of shipping a new gate as warn-only for one release.

3. **Waivers with a written reason.** A person can lift a blocking finding by adding a line to
   `security-waivers.md` in the change folder. The line names the finding (its rule and file), says
   whether it is an accepted risk or a false alarm, and gives a reason. A line with no reason doesn't
   count, the same rule the `Size waiver:` line follows in `bin/specclaw-verify`.
   - A small script decides which BLOCK findings are still unwaived; the model never decides that.
   - The PR body lists every waiver, so a reviewer sees what was accepted and why.

4. **Rules and practice tests for the recurring findings that are still missing.** Plan starts with
   a gap check: each recurring finding from the reports is compared with the base and stack presets,
   the review packs and the existing practice tests. Each finding not yet covered gets:
   - one preset line in the right preset;
   - one matching review-pack rule;
   - one practice test, written as an invented bad sample and a fixed sample with an `expect` line.

   The likely gaps (the gap check confirms them):
   - ownership and role checks that fail open when identity is missing;
   - security settings that fall back to "off" instead of refusing to start;
   - user input built into outbound URLs without encoding;
   - a token or credential taken from request data in place of the caller's identity;
   - redirect targets read from the request;
   - a real-client-IP and auth rate-limit rule for dotnet and python (node has one, they don't);
   - "not found" vs "forbidden" answers that reveal which resources exist.

   The practice-test runner today always loads base + node rules. It will load the stack that
   matches each sample's file type, so dotnet and python cases are scored against their own rules.

## Scope

### In Scope
- `bin/specclaw-build-context`: the stack security section, with its test.
- `templates/config.yaml`: `security_review: true`, the new `security_review_block: false` key, and
  comments.
- `bin/specclaw-pr`: the block check and the list of waivers in the PR body. The verify reference
  prose (step 3.52) is updated to match.
- A waiver checker script with its test. Its format is documented in `agents/infosec-reviewer.md`
  and the verify/pr references.
- Preset lines in `plugins/specclaw/presets/*.md` and review-pack rules in
  `plugins/specclaw-review/review-rules/*.md`, for the gaps the plan confirms.
- Practice tests in `plugins/specclaw/tests/evals/infosec/<case>/`, one per new rule, and the
  stack-aware runner fix.
- New tests registered in `.github/workflows/ci.yml`.
- One patch version bump across every manifest (rule R1).

### Out of Scope
- Making blocking the default for everyone. That is a later change.
- The "learn from a Shannon report" command and the findings log. That is the
  next change.
- A whole-project security check, the Shannon config generator, and the risks Shannon
  doesn't test, such as secrets scanning and dependencies.
- A security step in the **lean** flow. Lean builders already read presets; a lean reviewer step is
  a later change.
- The 6 open 069 follow-ups where a preset and its pack copy disagree. That change tracks them.
- Any client data from the reports. Samples and rules are invented and generic, and no
  Shannon prompt text or schema is copied (AGPL).

## Impact

- **Size:** bounded. It alters existing flows: build context, the `pr` gate, config, presets and
  packs. It adds no new subsystem; the waiver file is a small, local format.
- **Files affected:** about 20 (estimated), plus the version files.
- **Complexity:** medium.
- **Risk:** medium.
  - Turning the reviewer on by default adds one model call per change at plan and verify, plus one
    per build task that touches an entry point, for every SpecClaw user.
  - Blocking is opt-in, so a false alarm can't stop anyone who hasn't chosen it.
  - Expected to stay under the 400-line production cap (tests excluded). If the plan shows it
    won't, it gets split rather than waived.

## Open Questions

- This builds on 069 and 070, which are only on this fork branch. Does it go upstream as one PR with
  them, or as its own PR after they merge?
- Turning `security_review` on for everyone changes behaviour and cost for outside users too. Is
  "on and warn-only" acceptable to the upstream maintainer, or does step 1 need to ship off with a
  one-line opt-in?
- Where should a waiver line point: a rule + file pair (survives line moves), or the exact finding
  heading (precise, but breaks when the report is regenerated)? Proposed: rule + file.

---

**To proceed:** Review this proposal and approve to begin planning.
