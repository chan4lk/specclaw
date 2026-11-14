---
name: review
description: Use when a change is built and needs review before its PR, when verify runs and specclaw-review is installed, or when the user asks to review, re-review or run the review loop locally.
---

# specclaw-review: the local review loop

The loop runs **on this machine**. Rounds are cheap model calls, so the build server never runs a review
round. You push **once**, after the verdict is clean.

Tools: the `specclaw-review` MCP server (`review_run`, `review_verdict`, `memory_query`…), or the
`specclaw-review` CLI. Both run the same code. **Never read `.specclaw/review-memory/` directly.** Use
`memory_query`.

## The loop

1. **Round 1, the whole change:** `specclaw-review run --change <change>`.
   - **Exit 0:** clean. Go to step 4.
   - **Exit 1:** blocker/major findings are open. Go to step 2.
   - **Exit 3:** the review **did not run**. Report the error and stop. Never treat it as clean.
   - **Exit 4:** **escalate.** The same finding survived two fixes. Stop patching and do step 3.
2. **Fix by class, not by case.** For each blocker or major:
   - Find every variant: other spellings and locales, every caller, every second copy of the logic.
     `memory_query` with the touched files shows what this repo has already been bitten by.
   - Fix them all in one change. Prefer a structural fix (a closed vocabulary, one shared function, an
     explicit "not run" state) over another special case.
   - Add a **table-driven variant test** that fails without the fix: the named case plus at least two more.
   - Run the project's tests, then commit. Do **not** push.
   - Re-review only what changed: `specclaw-review run --change <change> --since <head of the previous round>`.
     The round file (`review/round-<n>.json`) records `head`. Code merged from the base branch is excluded
     automatically.
   - **Fix proof** (`review.fix_proof`, default `warn`). That `--since` round first checks the fix: the test
     files the fix added or changed (by `review.test_paths`, with common defaults) run with
     `review.test_command` (`{files}` expands to them) in a clean checkout of the pre-fix commit, where they
     must fail, and of HEAD, where they must pass. Any other outcome is `not proven: <reason>`. Set
     `test_command`, for example `test_command: "pytest -q {files}"` or `"bash {files}"`.
     - The proof is per round. The reviewer decides which findings are fixed: the `--since` re-review
       re-reports a finding or does not.
     - `block`: a not-proven round re-opens every blocker and major the reviewer closed in it
       (`carried: fix not proven: <reason>`). A final pass right after a not-proven round checks again.
     - `warn`: the proof runs the same way, but closed findings stay closed. `not proven: <reason>`
       (also for a missing `test_command`) is shown on the round file, in the CLI output
       (`fix-proof (warn): …`), in `review_run`'s `fix_proof_note` and in the verdict line.
     - `off`: no proof runs and nothing is recorded.
     - In `warn` and `block`, a finding whose file does not exist at HEAD (renamed or deleted) is carried
       (`file renamed or deleted`) in every later round: the reviewer cannot re-report it on the old path.
     - Any other value is refused with an error.
   - Repeat until a round exits 0. **There is no round cap.** Minors never trigger another round: they land
     in `follow-ups.md`.
3. **Escalation (exit 4).** Tell the user which finding repeats and propose a redesign of that part. Continue
   only on their decision.
4. **Final pass:** `specclaw-review run --change <change> --final`. This is the whole change, on the stronger
   model.
   - **Exit 1:** go back to step 2.
   - **Exit 0:** `specclaw-review verdict --change <change>` must exit 0. That means clean, with the final
     pass at HEAD.
5. Commit the round records (`.specclaw/changes/<change>/review/`, `follow-ups.md`) and the memory file
   (`git add .specclaw`). Then push **once**: `/specclaw:pr`.

## Recall at plan and build

The plugin's hook hands up to `review.recall_k` (default 3) past lessons to `/specclaw:plan <change>` and
`/specclaw:build <change>` as yes/no checks: the change's own `lesson` lines first, then review memory for
the files the change names, then similar lessons of other changes. Answer each. A "no" needs a task or a
fix. A recall that fails says `recall unavailable`, and the work goes on.

## The clean-loop PR status

`/specclaw:pr` (`specclaw-pr`) and `specclaw-azdo-pr` post a `specclaw/review-loop` status (`clean`) on the
PR once it exists. Branch policy can require it. They post only when
`specclaw-review verdict --change <change> --head <pr-head-sha>` exits 0: the verdict is clean **and** the
final pass ran at that SHA, or the net change from the final pass to that SHA touches only `.specclaw/` paths. So the round
records (step 5) and the PR bookkeeping commit keep the status. A commit that touches any other path, docs
included, gets no status. The `ci/` templates post the same status from the pipeline. Nothing here approves
or merges a PR.

## Fast track and the release gate

```yaml
review:
  fast_track: all            # or [<change>, ...]; off by default
release_gate:
  block_on: [law, security, data-loss]   # the default
```

- **Fast track.** For a covered change, every `run` is the final pass: one round over the whole change.
  Only `blocker` findings whose class is in `release_gate.block_on` must be fixed. Every other finding goes
  to `.specclaw/debt.md` through the review writer, never by hand. Tick an item (`- [x]`) when it is fixed.
- **Class.** Each finding carries `class`: `law`, `security`, `data-loss` or `other`. A blocker or major
  the reviewer left unlabelled is written as `unclassified` (fail closed): an unlabelled blocker keeps the
  fast-track round open, and an unlabelled major goes to `debt.md` and blocks at release. An unlabelled minor
  is `other`.
- **Release gate.** `specclaw-sync release <base> <target>` (from specclaw-sync) lists every open
  `debt.md` and `follow-ups.md` item that the range adds. It exits 1 only when an item's class is in
  `block_on`, or is `unclassified`. Other debt is listed and released.
- **Closing an item.** Tick a `debt.md` item (`- [x]`) when it is fixed. A `follow-ups.md` line has no
  checkbox: delete it, or change its leading `- [` to `- [x] [`, when it is fixed.

## Rules

`specclaw-review rules` prints the exact rulebook, in this order:
1. `base`;
2. the packs for this project's presets;
3. `.specclaw/review/rules/*.md`;
4. every file matched by `review.governance`, read fresh each round.

To add a repo rule, write it in `.specclaw/review/rules/` or run the `learn` skill.

## Config reference

Settings under `review:` in `.specclaw/config.yaml` that the loop reads beyond models and passes:

| Key | Default | Meaning |
|-----|---------|---------|
| `test_command` | none | Runs the fix's tests; `{files}` expands to them (appended when absent) |
| `test_paths` | common test globs | Which changed files count as tests for the fix proof |
| `fix_proof` | `warn` | `block`: an unproven fix keeps findings open. `warn`: report `not proven` and let them close. `off`: no proof. Anything else is an error |
| `learn_threshold` | `3` | `learn` proposes a lesson seen in this many changes |
| `recall_k` | `3` | Lessons the recall hook hands to plan and build |

## Matching an existing PR review

To make local rounds as thorough as a server-side review the project already trusts, mirror it in config:

```yaml
review:
  models: { round: opus, final: opus }     # heavy governance: Opus rounds cost the same ~1–3 min
  passes: [review, design]                 # standards pass + design-soundness pass
  tools: "Read,Grep,Glob"                  # let the reviewer open source and design docs
  max_turns: 12
  governance:                              # the files the server review inlines, read live
    - "CLAUDE.md"
    - "**/CLAUDE.md"
    - "docs/plans/CODE-CONVENTIONS.md"
```

Defaults are `round: sonnet` and `final: opus`. On replays of 5 real PR cycles, Sonnet rounds matched about a third of
the server's round-1 majors at major severity, while Opus rounds matched about two thirds, in the same 1–3 min.
For a repo whose PRs are judged by Opus, use Opus for rounds too.

With `governance` set, severity follows the project's own rules (`severity: project`, the default then). The
plugin's own rule ("a major needs a concrete scenario") applies only to repos without governance. In replays,
the plugin's own severity rules halved the majors filed against a repo whose governance defines what is major.

Docs are part of every reviewed diff, so code and README can be checked against each other. A finding on a doc
is never above minor, and a docs-only change skips review.
