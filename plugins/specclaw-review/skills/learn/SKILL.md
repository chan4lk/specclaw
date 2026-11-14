---
name: learn
description: Use when the user wants the review rules to learn from past review findings, to promote recurring lessons into repo rules, or to import an existing pitfalls/standards file into specclaw-review rules.
---

# specclaw-review: learn rules from this repo's own review cycle

Rules are never written silently. Every write needs the human's yes.

## Promote recurring lessons

1. Run `specclaw-review learn` (or call the `learn_propose` MCP tool). It is a dry-run that lists the lessons
   seen in `review.learn_threshold` (default 3) or more changes, each with its fingerprint. The review loop
   counts a lesson once per change.
2. Show the list to the user. For each lesson, ask whether a **guard test** (an automated check) would be better
   than a prose rule. A guard is what actually changes behaviour; a rule only reminds the reviewer. If they want
   a guard, propose it as a new change instead.
3. On a yes, run `specclaw-review learn --apply <fp> [<fp>…]`. That appends `L<n>` rules to
   `.specclaw/review/rules/learned.md` and marks those lessons `ruled`.

## Bootstrap from existing files

For a repo that already keeps review knowledge, such as a `REVIEW-PITFALLS.md`, reviewer standards or agent
hints:

1. Run `specclaw-review learn --import <file>…` first. This is a dry-run: show the user what would be written.
2. On a yes, re-run with `--apply`. Each file becomes `.specclaw/review/rules/imported-<name>.md`.
3. Run `specclaw-review rules` and show the size of the resulting rulebook. If it is very long, suggest trimming
   the imported files to the rules that still recur.
