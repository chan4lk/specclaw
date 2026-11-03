# Spec: specclaw-review — a local review loop that converges

**Change:** 044-fast-review-loop
**Created:** 2026-10-16
**Status:** 🟢 Approved (operator: "plan and build … go YOLO", 2026-10-16)

## Overview

A new add-on plugin, `plugins/specclaw-review/`, that runs a project's PR review loop **locally**:

1. review the change;
2. fix;
3. re-review the fix diff plus its impact set;
4. stop when a round has no blocker/major findings;
5. run one final whole-change pass on a stronger model;
6. push once.

Review rules come from layered packs, like presets: plugin packs plus the repo's own
`.specclaw/review/rules/`. Lessons live in a repo-committed, bounded review memory that is reached only through
the plugin's MCP server. Core `verify`/`pr` (lean and full) call the plugin only when `specclaw-review` is on PATH.
Evidence: `findings.md`.

## Requirements

### Functional Requirements

- **FR-1 Rulebook.** `specclaw-review rules` prints the resolved rulebook:
  - `base` always comes first;
  - then the packs named by `review.rules`, or, when that key is unset, the project's `presets:` list. Unknown
    names are skipped with a note;
  - then every `*.md` under the repo rules dir (`review.repo_rules`, default `.specclaw/review/rules`), in name
    order;
  - then a `## Severity overrides` section rendered from `review.rule_overrides`.

  The plugin ships `review-rules/{base,python,node,react-spa,nextjs,dotnet}.md`. Every rule has a stable ID
  (`B1`, `PY2`…). `base.md` carries the generic lessons from Project A's loop: class-not-case, a variant test per fix,
  never-clear-on-did-not-run, no second copy, pin what you read, fail-closed input, and severity calibration.
- **FR-2 Classify.** `specclaw-review classify [--range A..B]` prints `skip` or `review`, and the changed files.
  - **`skip`:** returned only when every changed path matches a skip glob (default: `.specclaw/**`, `*.md`,
    `docs/**`, lockfiles, `*.generated.*`, plus `review.skip_paths`).
  - **Risky paths:** a match on `review.risky_paths` makes every round use the final model.
- **FR-3 Round.** `specclaw-review run --change <c> [--since <sha>] [--final]` runs one round. It:
  - builds the prompt: rulebook, memory slice, diff, impact set, prior open findings, output contract;
  - calls the backend;
  - parses findings (JSON array: severity, rule, file, line, message, scenario, in_delta);
  - writes `changes/<c>/review/round-<n>.json`;
  - upserts memory;
  - prints a summary.

  **Diff scope:**
  - without `--since`: `merge-base(base, HEAD)..HEAD`;
  - with `--since`: only non-merge first-parent commits `since..HEAD`, so code merged from the base branch is
    excluded;
  - `--final`: always the whole change, on `review.models.final`.

  **Exit codes:**
  - 0: no blocker/major;
  - 1: blocker/major remain;
  - 3: review did not run (backend error, unparsable output, empty diff while not skipped). Fail-closed: the
    round file records `status: not_run`;
  - 4: escalate (the same rule in the same file filed as blocker/major in ≥ 2 earlier rounds of this change;
    keyed on rule + file, because a message fingerprint changes wording between rounds);
  - 2: usage.
- **FR-4 Impact set.** For a round, the plugin extracts the names of functions, classes and consts added or
  changed in the diff hunks. `git grep -l -w` finds the other tracked files that reference them, capped by
  `review.impact_cap` (default 20). Their paths and the matching lines go into the prompt, together with the
  files of earlier findings in this change.
- **FR-5 Severity calibration (enforced in code, not just prompt).**
  - After parsing, a `major` or `blocker` with an empty `scenario` is downgraded to `minor`.
  - A finding whose file matches a skip glob is capped at `minor`.
  - Duplicates (same file + rule + line ±3) collapse to one.
  - `in_delta: false` findings that are not blockers are tagged `pre-existing` and never count toward exit 1.
- **FR-6 Loop state and verdict.** `specclaw-review verdict --change <c>` prints one line:
  `Review: CLEAN|OPEN|ESCALATE|NOT_RUN — <n> rounds, final pass <sha|missing>, models <round>/<final>`.
  - **Exit codes:** exit 0 only when the latest round is clean, a final pass exists, and that final pass's
    `reviewed_sha` equals HEAD; otherwise 1.
  - **`--pr-line`:** prints the line for a PR body.
  - **Follow-ups:** minors from every round are appended once (deduped) to `changes/<c>/follow-ups.md`.
- **FR-7 Backend.** `review.backend` is a command template, read on stdin and printed on stdout, with `{model}`
  substituted. The default is
  `claude -p --model {model} --tools "" --setting-sources "" --strict-mcp-config --no-session-persistence --output-format text`.
  Defaults are `review.models.round: sonnet` and `review.models.final: opus`; Haiku was dropped after the replays (see
  `smoke-replay.md`). No network or service is assumed
  beyond that command.
- **FR-8 Memory.** `findings.jsonl` under `review.memory_dir` (default `.specclaw/review-memory/`). The core
  library offers `memory_put`, `memory_query` and `memory_compact`:
  - **put:** dedupes by fingerprint `sha1(rule | top-2 path segments | first 8 normalised words)`. A repeat
    bumps `count` and `last` and merges `files`.
  - **query:** given files and a token budget (default 1500, approx chars/4), returns the top-k (default 10)
    active entries. Score: same file 3, same dir 2, same top dir 1, + severity, + log2(count).
  - **compact:** removes retired entries, and entries whose files are all gone and whose `last` is older than
    `decay_days` (180). It then enforces `max_entries` (2000) by score.
- **FR-9 MCP server.** `mcp/server.py` is a stdio JSON-RPC 2.0 MCP server (python3, stdlib only) registered by
  the plugin's `.mcp.json`. Tools: `review_rules`, `review_classify`, `review_run`, `review_verdict`,
  `memory_query`, `memory_put`, `memory_compact`, `learn_propose`, `review_stats`. Each calls the same core
  library the CLI uses.
- **FR-10 Guards.** The plugin's `hooks/hooks.json` registers a `PreToolUse` hook (`hooks/guard-memory`):
  - **Denied:** `Read`, `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Grep` and `Glob` calls whose path or
    pattern touches the memory dir, and `Bash` commands that name it.
  - **Deny reason:** points to the `memory_query` MCP tool.
  - **Allowed:** everything else, with no output.
  - **Rules file:** `specclaw-review init` writes `.claude/rules/specclaw-review-memory.md` stating the same rule,
    for hosts without hooks.
- **FR-11 Learn.**
  - **`specclaw-review learn`:** prints proposed rules (dry-run) for active memory entries with `count ≥ 2` that
    are not yet marked `ruled`. `--apply <fp>…` appends them to `<repo_rules>/learned.md` with IDs `L<n>` and
    marks those entries `ruled`.
  - **`learn --import <file>…`:** dry-run lists what would be copied. `--apply` writes each file to
    `<repo_rules>/imported-<basename>.md` with a source header. Nothing is written without `--apply`.
- **FR-12 Stats.** `specclaw-review stats` reads `changes/*/review/round-*.json`, archive included. It prints, per
  change, the rounds, the blocker/major/minor counts per round with the model used, and the wall time. Overall it
  prints median rounds, median time-to-clean, and blocker/major per round by model.
- **FR-13 Lazy init, zero config.** Every command:
  - creates the repo rules dir (with a README) and the memory dir when it needs them;
  - adds `.specclaw/review-memory/*.jsonl merge=union` to `.gitattributes` once.

  Config is optional: every key has a default, and the `review:` block is read block-scoped.
- **FR-14 Core hooks (lean + full).** Each hook runs only after a
  `command -v specclaw-review >/dev/null 2>&1` guard; when the plugin is absent, nothing runs.
  - **Verify:** lean `skills/verify/SKILL.md` and full `references/full/verify.md` gain an optional step: run the
    local loop (skill `specclaw-review:review`), then record `specclaw-review verdict` under `## Verify` (lean) or
    in `verify-report.md` (full).
  - **PR body:** `specclaw-pr` and `specclaw-azdo-pr` add the `--pr-line` output under the Verdict line.
  - **PR skills:** lean and full `pr` warn when the verdict does not exit 0.
- **FR-15 Skills.** `skills/review/SKILL.md` drives the loop:
  1. run rounds;
  2. make class fixes with variant tests;
  3. escalate on exit 4;
  4. run the final pass;
  5. single push.

  `skills/learn/SKILL.md` asks the human before any `--apply`.
- **FR-16 CI snippets.** `ci/azure-pipelines.yml` and `ci/github-actions.yml` run
  `specclaw-review verdict --check-head` and nothing model-backed.
- **FR-17 Packaging.** The plugin ships Claude and Codex manifests at the shared version, entries in both
  marketplaces, and the version bump across all manifests.

- **FR-18 Passes.** `review.passes` (default `[review]`) runs one backend call per pass on the same prompt
  context:
  - `review`: the complete standards review;
  - `design`: design and implementation correctness, with invariants and failure modes;
  - an unknown pass name → exit 2.

  Findings carry `pass`. Findings from different passes on the same file within ±3 lines collapse to one.
- **FR-19 Tools.**
  - `review.tools` (default `""`) gives the reviewer read-only tools, e.g. `Read,Grep,Glob`.
  - `review.max_turns` defaults to 12 when tools are set, else 1.
  - The default backend passes the rulebook through `--append-system-prompt-file`, with `--permission-mode
    dontAsk`, and denies `Read(~/.claude/**)`.
  - Custom templates may use `{model}`, `{tools}`, `{max_turns}` and `{system_file}`. Without `{system_file}`,
    the rulebook is prepended to stdin.
- **FR-20 Live governance.** `review.governance` (a list of globs over tracked files) is read fresh on every round
  and appended to the rulebook after the repo rules, each under its path. It is never copied.
- **FR-21 Docs visible.** Classification still returns `skip` when only records/docs/generated files changed.
  For a reviewed change, docs (`*.md`, `docs/**`) are included in the diff, and findings on them are capped at
  minor. Excluded paths (`.specclaw/**`, lockfiles, generated, `review.skip_paths`) never enter the diff.

- **FR-23 Severity policy.** `review.severity: plugin|project`. With `project`, the repo's governance sets
  severity: the preamble defers to it, the scenario requirement leaves the output contract, and a scenario-less
  major is not downgraded. It defaults to `project` when `governance` is set, and to `plugin` otherwise.
- **FR-24 Review hardening (from the verify code review).**
  - `--since` is resolved to a commit sha, so it can never reach git as an option.
  - A finding with an unknown severity is mapped (critical → blocker, unknown → major), and one with no file is
    kept. Parsing never drops a finding.
  - A final pass that is no longer in HEAD's history (rebase, shallow clone) is a not-OK verdict with a reason.
  - A lesson counts once per change in memory.
  - The guard matches the configured `memory_dir` as a path segment.
- **FR-22 Discover + rules skill.** `specclaw-review discover [--json]` is a deterministic, read-only scan of
  tracked files. It reports:
  - **governance candidates**, by category: agent instructions, conventions, review standards/pitfalls, and
    decisions/ADRs (read with tools, not inlined). Each comes with its line and char counts, and fixtures, vendor
    trees and change records are excluded;
  - the total rulebook size if the candidates are adopted, with a warning above `review.governance_budget`
    (default 200 k chars);
  - whether those files define severity;
  - the existing repo rules, learnings/follow-ups counts, and learn candidates;
  - whether a PR host can be read: `gh` authenticated, or Azure DevOps configured with a token present. The
    token is never printed;
  - a suggested `review:` block.

  Nothing is written. The MCP server exposes it as `review_discover`. `skills/rules/SKILL.md` turns the scan into
  config and rule files, writing only after approval.

### Non-Functional Requirements

- **NFR-1** The plugin uses stdlib python3 + bash + git only, with no third-party packages and no network except
  through the configured backend command.
- **NFR-2** The test suite is offline: the backend is stubbed through `review.backend`. It is registered in
  `.github/workflows/ci.yml`.
- **NFR-3** A `memory_query` result never exceeds its token budget, whatever the file size.
- **NFR-4** Core keeps working with the plugin absent (guarded by `command -v`).
- **NFR-5** Change names and paths are never interpolated into a regex or an unquoted shell string.

## Acceptance Criteria

- **AC-1** `rules`: base first; packs from `review.rules`, else from `presets:`; then repo rules in name order;
  then overrides. An unknown pack yields a note and no failure.
- **AC-2** `classify` returns `skip` for a records/docs-only range and `review` when any code file changed. A
  risky path selects the final model.
- **AC-3** `run` with a stub backend writes `round-1.json`. Exit codes: 1 when a major with a scenario is
  returned, 0 when only minors are returned.
- **AC-4** Backend failure or unparsable output → exit 3, `status: not_run`, and never a clean verdict.
- **AC-5** Calibration: a scenario-less major → minor; a skip-glob file → minor; duplicates collapse;
  out-of-delta non-blockers do not count.
- **AC-6** `--since` excludes code merged from the base branch (a merge commit's content is absent from the
  prompt diff).
- **AC-7** The impact set lists another file that references a changed function name.
- **AC-8** The same rule in the same file open in 2 earlier rounds → exit 4 / `ESCALATE`.
- **AC-9** `verdict` exits 0 only with a clean latest round, a final pass, and `reviewed_sha == HEAD`. A new
  commit after the final pass makes it exit 1.
- **AC-10** Memory: a repeat put bumps `count` and adds no row; the query output stays ≤ budget with 5,000 entries
  in the file; compact enforces `max_entries` and drops retired entries.
- **AC-11** The guard hook denies Read/Edit/Write/MultiEdit/NotebookEdit/Grep/Glob/Bash on the memory path,
  allows unrelated paths, and the deny reason names `memory_query`.
- **AC-12** The MCP server answers `initialize`, `tools/list` (all 9 tools) and a `tools/call` of `memory_query`
  over stdio.
- **AC-13** `learn` is a dry-run by default (no file written). `--apply` writes `learned.md` and marks entries
  `ruled`. `--import` copies only with `--apply`.
- **AC-14** `stats` prints the median rounds and per-model blocker/major per round from fixture round files.
- **AC-15** Lazy init creates the rules dir, the memory dir and the `.gitattributes` line once (idempotent).
- **AC-16** Core: `specclaw-pr` includes the review line when `specclaw-review` is on PATH and is byte-identical
  without it. Lean and full verify/pr docs carry the guarded step.
- **AC-17** All manifests and marketplaces carry the plugin at one shared version. The Codex packaging tests pass.
- **AC-18** A real smoke run on a Project A change, done locally with no push, completes a round with the
  real backend and produces a round file and a verdict line.

- **AC-19** `passes: [review, design]` makes two backend calls. Each finding records its pass, and a design
  finding on the same file within ±3 lines of a review finding collapses into it.
- **AC-20** With `tools` set, the default backend argv carries `--allowedTools <tools>`, `--max-turns 12`,
  `--append-system-prompt-file` and `--permission-mode dontAsk`. With none set, it carries `--tools ""`.
- **AC-21** A `governance` glob's file appears in `specclaw-review rules`. Editing the file changes the next
  rulebook with no import step.
- **AC-22** A code change plus a README: the README's hunk is in the reviewed diff, and a README finding is capped
  at minor. A README-only change classifies as `skip`.
- **AC-23** Project A parity replay: in "match Project A" mode (Opus, review+design, Read/Grep/Glob, Project A's governance
  globs), the replay of PR A at its first-iteration head is compared with the server's round-1 major groups and reported
  in `smoke-replay.md`.

- **AC-24** `severity: project` keeps a scenario-less major and drops the scenario gate from the prompt. With
  `governance` set, it is the default.
- **AC-27** FR-24: an option-like `--since` is refused and no file is written; unknown-severity and file-less
  findings are kept; a still-open finding is not re-counted; a rebased-away final pass gives exit 1 with a
  reason; the guard allows `specclaw-review-memory.md` and guards a configured `memory_dir`.
- **AC-25** `discover` lists CLAUDE.md, AGENTS.md, a conventions doc and a pitfalls file as governance; ADRs as
  read-with-tools; and nothing under fixtures, `node_modules` or `.specclaw/changes`. It flags severity when a
  candidate defines blocker/major. It prints a `review:` block whose `governance` names the candidates, and it
  writes no file.
- **AC-26** Over budget, `discover` warns and still lists the files. `--json` is valid JSON. The MCP
  `tools/list` has 10 tools, including `review_discover`.

## Edge Cases

- An empty diff for a `skip` classification is clean: no backend call, and the round is recorded as `skipped`.
- No git repo, or no base branch → exit 2 with a message.
- A memory file with a corrupt line: the line is skipped with a stderr warning and never fatal. Compact rewrites
  the file without it.
- Backend output wrapped in prose or code fences: the first JSON array is extracted. No array → exit 3.
- A change name containing regex or shell metacharacters.
