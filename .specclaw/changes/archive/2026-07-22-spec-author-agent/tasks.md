# Tasks: Spec Author Agent

**Change:** spec-author-agent
**Created:** 2026-05-24
**Total Tasks:** 4

## Summary

Four tasks across two waves. Wave 1 ships the agent + standalone skill (independent files). Wave 2 wires the flag into `/specclaw:plan` and updates the README. Self-test of the new flow happens in `/specclaw:verify`, not as a separate task.

## Tasks

### Wave 1 — Create agent and standalone skill

- [x] `T1` — Create `spec-author` subagent
  - Files: `plugins/specclaw/agents/spec-author.md` (new)
  - Estimate: medium
  - Depends: —
  - Notes: Frontmatter with `name: spec-author`, `description`, `tools: [Read, Write, Bash]`, `model: opus`. System prompt instructs the agent to:
    (a) read `.specclaw/changes/<change>/proposal.md`;
    (b) walk `templates/spec.md` section-by-section (Overview → FRs → NFRs → ACs → Edge Cases → Dependencies → Notes);
    (c) ask ≥1 grounded clarifying question per section, applying a named brainstorming/challenge technique appropriate to the section — embed a small mapping table in the prompt: **5 Whys** (Overview/Problem framing), **Jobs-to-be-Done** (Functional Requirements), **Inversion** (Non-Functional Requirements: "what would make this useless?"), **Pre-mortem** (Edge Cases: "imagine it shipped and broke — what broke?"), **MoSCoW** (scope-creep challenges), **Concrete-example probe** (any abstract claim);
    (d) name the technique to the user before using it (e.g. "Let's do 5 Whys here — why…");
    (e) push back on vague/untestable requirements ("fast", "easy", "secure") and require an observable threshold before writing them into the spec — implements FR3b;
    (f) write the final spec to `.specclaw/changes/<change>/spec.md` in a single `Write` call only after the user confirms the last section.
    Reference `references/agent-guardrails.md` Rules 1 & 2.

- [x] `T2` — Create `/specclaw:author-spec` skill
  - Files: `plugins/specclaw/skills/author-spec/SKILL.md` (new)
  - Estimate: small
  - Depends: —
  - Notes: Frontmatter `description` follows the pattern of `skills/plan/SKILL.md`. Steps: (1) `specclaw-ensure-init .specclaw`, (2) `specclaw-validate-change .specclaw <change> plan` — abort on failure, (3) if `.specclaw/changes/<change>/spec.md` exists, ask the user to confirm overwrite (default no), (4) invoke `Agent(subagent_type=spec-author, prompt="Author the spec for change '<change>'.")`, (5) `specclaw-update-status .specclaw`, (6) GitHub/Azure sync if enabled (mirror what `plan/SKILL.md` does).

### Wave 2 — Integrate flag and document

- [x] `T3` — Wire `--author-spec` flag into `/specclaw:plan`
  - Files: `plugins/specclaw/skills/plan/SKILL.md` (edit)
  - Estimate: small
  - Depends: T1
  - Notes: Add a "Flags" section explaining `--author-spec`. In step 4, branch: if the flag is present in ARGUMENTS (matched as a whitespace-delimited token), invoke the `spec-author` agent for the spec step instead of generating `spec.md` inline, then explicitly STOP and require the user to type an approval before continuing to `design.md` / `tasks.md`. Strip the flag token before using the rest of ARGUMENTS as the change name. Use the same explicit "Do not proceed until approved" wording as `skills/propose/SKILL.md`.

- [x] `T4` — Document new skill and flag in README
  - Files: `README.md` (edit)
  - Estimate: small
  - Depends: T2, T3
  - Notes: Add a row `| /specclaw:author-spec <change> | Author spec.md interactively via the spec-author subagent |` to the Commands table. Add one sentence under the `/specclaw:plan` example noting that `--author-spec` can be appended for interactive spec authoring with an approval gate.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
