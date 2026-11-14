# Proposal: specclaw-review — a review loop that converges

**Created:** 2026-10-16
**Status:** 🟡 Draft
**Evidence:** [findings.md](findings.md) (spike on Project A: 172 PRs, 538 review rounds)

## Problem

In Project A, specclaw's largest user, the PR review loop works: it finds real defects. But it converges
slowly, and that, not the build, is where the time goes:

- 172 PRs took 538 review rounds. A round costs 20–70 min, sometimes up to 3 h. PR A took ~31 h to come clean.
- ⅓ of all branch commits are round records, and each one re-triggers ~18 min of CI and the review.
- **Late rounds are mostly real defects created by narrow fixes:** 16 of 24 sampled round-2+ majors. The fix
  patches the case the reviewer named, and the next round finds the next variant. Late rounds are not mainly
  reviewer churn. "Fix the class, not the case" has been a written lesson since 2026-10-01 and recurred in 8+ PRs
  after that. Prose lessons do not change behaviour.
- **Why `/specclaw:verify` never caught these** (see "Why verify missed it" below): verify checks acceptance
  criteria plus lint/tests. Project A switched verify's code review off on 2026-09-30, and the core reviewer does not use
  the project's rubric anyway. Every fix made during the PR loop happens after verify and never goes back
  through it.

## Why verify missed it, and the PR cycle caught it

1. **Different question.** Verify asks "does the build meet AC-1..n, and are lint and tests green?" The PR
   reviewer asks "does this diff break project law (its domain invariants, pins, second copies…)?"
   The defects found were almost never AC failures. They were class and rubric violations, which the ACs do not
   encode.
2. **The local reviewer was off.** Project A `config.yaml`: `workflow.code_review: false # Off (product owner,
   2026-09-30): the PR review loop is the only review`. No change since then has a `review-report.md`, and
   `build.task_review` (035) is not enabled either.
3. **Different rubric even when it was on.** Core's `code-reviewer` runs ten generic dimensions on Sonnet. Project A's
   PR review runs two Opus passes inlined with every CLAUDE.md, its code conventions and its pitfalls file. The local
   reviewer never saw the rules the PR is judged by.
4. **Verify runs once, before the loop.** Every round-2+ fix is written during the PR loop, after verify has
   passed. Those fixes produce the late-round majors, and none of them is re-verified locally. The server is the
   only reviewer they ever meet.
5. **A single review run is a sample.** Even Project A's pre-PR `code-reviewer` runs (PRs 285, 294) were followed by
   round-1 majors. One pass finds one subset, so the loop must be cheap to repeat locally, not skipped.

## Proposed Solution

A new, self-contained plugin **`specclaw-review`** (alongside specclaw-sync / specclaw-extras). It is universal:
any model the host CLI can call, any CI, no machine-specific services. Core gets only an optional hook: `verify`
and `pr` call `specclaw-review` when it is on PATH and skip silently otherwise, the same pattern as party and
gh-sync.

**A. The review loop runs locally, not on the build server.** `specclaw-review loop` runs on the developer's
machine:
1. review the change;
2. fix;
3. re-review the fix diff plus its impact set;
4. repeat until a round returns **no blocker or major findings** (no round cap);
5. do the final whole-change pass;
6. push **once**.

Round records stay local until that push, so no round triggers a build. CI goes back to tests and lint on one
push. A CI review becomes optional: a reference snippet confirms that `reviewed_sha` matches HEAD instead of
re-reviewing. For Project A, the review rounds that cost ~18 min of CI each become local rounds that cost only the
model call. Verify runs the same loop on the whole change, so verify and PR-time judge by the same rules.

**A2. Review rules are layered, like presets.** The plugin ships rule packs in `review-rules/`:
- `base.md` is always on. It holds the **generic lessons distilled from Project A's 538 rounds**: fix the class, not
  the case; a variant test per fix; "did not run" never reads as clear; no second copy of logic; pin what you
  read; fail-closed on missing input; severity calibration.
- Per-stack packs mirror `presets/`: python, node, react-spa, nextjs, dotnet.

The repo adds its own rules in **`.specclaw/review/rules/*.md`**. That is where repo-specific law lives: for
Project A, its own domain rules. Config selects and orders the packs:

```yaml
review:
  rules: [base, python, react-spa]   # plugin packs, like `presets:`
  repo_rules: .specclaw/review/rules # repo-owned, always appended
  rule_overrides: {}                 # e.g. raise or lower a rule's severity
```

`specclaw-review rules` prints the resolved rulebook, the exact text the reviewer receives. Nothing
repo-specific ever ships in the plugin.

**A3. Learn from the repo's own cycle.** `specclaw-review learn` reads the project's own history: closed
findings in the review memory, `learnings.md` and `follow-ups.md`. It **proposes** a new or sharpened rule for
`.specclaw/review/rules/`, or a guard test for a lesson that recurs. A human approves each one, as with
`/specclaw-extras:learn`. `specclaw-review learn --import <path>…` bootstraps a repo from existing files (for
Project A: its pitfalls file, its reviewer standards, its agent hints), so Project A's PR cycle seeds Project A's rules on day
one.

**B. Fixes must prove the class (the main lever).** For each blocker or major being fixed, the fix gate requires:
- a table-driven variant test (spellings, locales, every caller), and
- a "where else does this pattern live?" search over the impact set.

The follow-up reviewer is asked "is this an instance fix?". The same finding surviving 2 rounds escalates to a
structural redesign or a human decision, never a third patch.

**C. Rounds that converge.**
- **Scope:** delta rounds review the PR's own changes plus their **impact set** (callers of changed symbols,
  earlier finding sites), excluding code merged from the base branch.
- **Final pass:** one **final whole-PR pass** replaces a blind stop rule. 397 r6 found 3 majors after a clean r5.
- **Severity calibration:** a round-2+ major needs a concrete failure scenario. Records, process docs and lint are
  never major. Pass A and B findings are deduped by root cause.
- **Pre-existing findings:** these are tagged and go to `follow-ups.md`.
- **No round cap. The loop runs until a round has no blocker/major findings.** Minors are recorded in
  `follow-ups.md` and never trigger another round. The only non-convergence guard is the repeat rule in B: the
  same finding surviving 2 rounds escalates to a redesign or a human decision instead of a third patch.
- **No CI for records:** round records stay local and ride along with the single push (see A).

**D. The most efficient model by default, host-agnostic.**
- **Loop rounds** run on the most efficient model the host offers, for example `claude-haiku-5-5` or the
  equivalent fast model elsewhere. Rounds are many and cheap, and the variant tests from B carry much of the
  load.
- **The final whole-change pass** runs once on a stronger model, by default the host's mid tier (e.g. Sonnet).
  This is the safety net for what a small model misses.
- **Diffs that only touch records, docs or generated files** are classified `skip` deterministically and get no
  model call.

Every choice is config (`review.models.round`, `review.models.final`). Backends are `claude -p --model …` or any
command that reads a prompt on stdin. `specclaw-review stats` reports findings per round by model, so a project
can see whether the small model is missing things before it trusts it further. If no backend answers, the result
is fail-closed and visible.

**E. The MCP server is the plugin's interface.** One stdio server (`specclaw-review-mcp`, Node, no network,
file-backed) exposes the whole surface as tools: `review_rules` (the resolved rulebook), `review_run` (one round
on a diff/range), `review_record` (findings → memory + round metrics), `memory_query`, `memory_put`,
`memory_compact`, `learn_propose` and `review_stats`. The bins and skills are thin wrappers over the same core,
so a CLI or CI run and an agent see identical behaviour.

**E2. Review memory: repo-local, bounded, accessed only through MCP.**
- **Storage:** `.specclaw/review-memory/findings.jsonl`, committed (`merge=union`), so it travels with every clone.
- **Access:** the plugin's own stdio MCP server is the **only** reader and writer. Tools: `memory_query` (top-k
  for the diff's files under a fixed token budget, ~1.5k), `memory_put`, `memory_compact`.
- **Bounded growth:** entries are deduped by fingerprint (repeats bump a count). A lesson that recurs is proposed
  as a **guard** (test or lint rule) and retired once the guard lands, because a guard is what changes behaviour.
  Stale entries decay, and the file has a hard cap.

**Guards against reading the file directly:**
- A plugin `PreToolUse` hook denies `Read`/`Grep`/`Glob`/`Edit`/`Write` on `.specclaw/review-memory/**`, and Bash
  commands that name the path (`cat`, `grep`, `head`, `sed`, `jq`…). The deny message points to `memory_query`.
- A rules file (`.claude/rules/review-memory.md`, or a CLAUDE.md block installed by `specclaw-review init`) says
  the same thing for hosts without hooks.
- The MCP server holds the only write path, and it re-validates the file on start.
- A test asserts that the hook denies every listed tool/path pair.

**F. Measure.** Rounds, wall time per round, tier, backend, and fix-induced vs pre-existing are recorded in
state.json. `specclaw-review stats` prints median rounds and time-to-clean, giving a re-runnable version of Project A's
its review-trend script for any project.

**G. Both flows, zero setup.**
- **Lean and full flows:** the optional hook goes in lean `verify`/`pr` (`skills/*/SKILL.md`) as well as full
  (`references/full/*.md`). Lean writes the review verdict as a line under `## Verify` in `change.md`, and full
  writes it to `review-report.md`. Absent plugin → both skip silently.
- **New repos are automatic:**
  - **Rule packs** are read from the existing `presets:` list, which `specclaw-init` already detects from
    manifests. `review.rules` only needs setting to override that.
  - **Created lazily on first use:** `.specclaw/review/rules/` and the memory file, plus the `merge=union` line in
    `.gitattributes`.
  - **The MCP server and the guard hooks** are registered by the plugin itself (`.mcp.json`, `hooks/hooks.json`),
    with no per-repo step.
  - **Model access** reuses the host CLI's existing login. No API key, no config.
- **What stays with a human, by design:** installing the plugin once (`/plugin install specclaw-review`), and
  approving each rule `learn` proposes. Rules are never written silently. Optional: `learn --import` for a repo
  that already has pitfall files, like Project A.

## Scope

### In Scope
- New plugin `plugins/specclaw-review/`: bins (`specclaw-review`, tier classifier, stats), the MCP server
  (stdio, no network, file-backed), the hooks, a rules template, skills, and a marketplace entry.
- Optional hooks in core `verify` / `pr` (on PATH → run; absent → skip silently). Core has no other dependency on
  the plugin.
- Fix-gate instructions and a variant-test requirement for the fix loop. A generic `pr-review-loop` skill.
- `specclaw-review loop` (local review→fix→re-review→final pass→single push) with round records kept local until the single push.
- Rule packs `review-rules/{base,python,node,react-spa,nextjs,dotnet}.md`; repo rules in `.specclaw/review/rules/`;
  `review.rules` / `rule_overrides` config; `specclaw-review rules` (print resolved rulebook).
- `specclaw-review learn` (propose rules/guards from the repo's own findings) and `learn --import` (seed from
  existing pitfall/standards files).
- Optional, minimal CI snippets (Azure DevOps, GitHub Actions) that only confirm `reviewed_sha == HEAD`.
- Lean + full hooks; zero-config defaults (packs from `presets:`, lazy dirs, plugin-registered MCP + hooks).
- Tests: classifier tiers, hook deny matrix, memory dedupe/compaction/token budget, MCP round-trip, the
  core skip-when-absent path.

### Out of Scope
- Editing Project A itself. Project A adopts the plugin, runs `learn --import`, and turns off its CI review in
  its own change.
- Any repo-specific rule in the plugin. Project A's law lives in Project A's `.specclaw/review/rules/`.
- CI speed in general (caching, pools) and the rebase / regenerated-client churn (394 commits) → a separate
  proposal.
- Any machine-specific model host or external memory service.
- Changing core `code-reviewer`, the party panel or 035's task gate, beyond calling the shared classifier.

## Impact

- **Size:** architectural. It is a new plugin with an MCP interface and a CI contract that other projects depend on.
- **Files affected:** ~25 (new plugin), ~4 in core (verify/pr refs, config template, marketplace)
- **Complexity:** large. It ships as three PRs: (1) A/A2+C+D local loop, rule packs, tiers; (2) A3 learn + B fix gate + F stats;
  (3) E memory MCP + guards.
- **Risk:** medium. A wrong `light` tier could under-review risky code: the classifier biases up and CI keeps the
  final say. The hook's Bash matching is best-effort, so the rules file and MCP-only writes are the backstop.

## Open Questions

1. The spike couldn't read ADO threads (az auth). Re-run the sample against the threads before tuning the severity
   rules in `base.md`?

## Decisions (2026-10-16, operator)

- Own plugin `specclaw-review`. It is universal, with no machine-specific hosts or services, and core stays
  untouched apart from optional hooks.
- The loop runs locally. The build server only runs tests/lint on one push.
- Review rules are layered like presets: plugin packs plus the repo's `.specclaw/review/rules/`.
- Reviews use the most efficient model, and the final pass uses a stronger one.
- There is no round cap: the loop runs until there are no blocker/major findings, guarded only by the repeat rule.
- The MCP server is the plugin's interface: rules, review, memory, learn, stats.
- Review memory is reached only through MCP, and hook and rules guards block direct reads.
