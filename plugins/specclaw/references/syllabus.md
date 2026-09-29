# Syllabus guide — recipe

An **opt-in**, human-facing study guide that teaching mode generates from the learner's level map.
It turns the assessment into a structured course the learner can read at their own pace, revisit
later, and publish (GitHub Pages, a wiki, a docs site).

The **syllabus and the two laws**: `teaching-mode.md` says documents are written only when the
step that needs them arrives. A syllabus is the one exception, and only because the learner
**asked for it**. So:

- **Never generate one unasked.** `teach.syllabus: ask` (default) means ask once, after the
  level map is shown. `always` skips the question. `never` suppresses the offer entirely.
- **It is a reference, not a prerequisite.** Build-time briefs still happen at the task that needs
  them. They link to the syllabus chapter instead of repeating it.
- **One chapter at a time is still the reading rule.** The guide's index says so, and every
  chapter ends by pointing to the task that uses it.

## When to offer it

At the end of `/specclaw:teach` Step 3 (level map shown), if `specclaw-teach .specclaw syllabus`
prints `ask` **and** at least one technology is rated (a) or (b):

> Six of your eight technologies are at (a) or (b). Do you want a **syllabus guide**: one
> chapter per concept, with diagrams, worked examples, curated articles and videos, and
> self-check questions, written to `docs/syllabus/` so it can be published?

Use `AskUserQuestion` with **Yes, generate it** / **No, briefs only**. A yes also runs on demand:
`/specclaw:teach syllabus`.

## Where it goes

```bash
specclaw-teach .specclaw syllabus-path    # teach.syllabus_dir, default docs/syllabus
```

It goes in the **project**, never in the plugin or under `.specclaw/`, because it is meant to be
committed and published.

```
docs/syllabus/
├── index.md             # scope, level map, reading order, how to use, chapter table
├── 01-<concept>.md      # one chapter per concept, numbered in first-needed order
├── ...
└── glossary.md          # every term used, one line each, linked to its chapter
```

If the project has no docs site, also write a minimal `mkdocs.yml` next to `docs/` only when the
user wants it published. Do not add CI or hosting config unasked.

## Scope: which concepts get a chapter

Derived from the level map, never from a generic curriculum:

| Level | Chapter |
|---|---|
| (a) never used | Full chapter |
| (b) theory only | Short chapter: skip definitions, cover what tutorials leave out (production concerns, failure modes, trade-offs) |
| (c) shipped | No chapter. One glossary line plus the "what's specific to this project" note |
| (d) deep | Nothing |

Split a technology into concepts when one chapter would pass ~2,500 words. Order chapters by
the task that first needs them, and name that task in each chapter.

## Chapter structure (in this order)

1. **Why this matters here.** Two or three sentences tied to *this* project's tasks, not a
   definition. Name the task ids or phases that use it.
2. **Mental model.** The one idea that makes everything else follow, and *where the analogy
   breaks*.
3. **Diagram.** At least one Mermaid diagram (flowchart, sequence, state or class) that shows the
   mechanism, not a decorative box chart. Mermaid renders natively on GitHub and in
   MkDocs Material.
4. **Core primitives.** 3–6 building blocks, each with a minimal code example in the project's
   own stack and style.
5. **Worked example.** One realistic example from this project's domain, step by step.
6. **Common mistakes.** 3–5, each with the symptom you'd see and the fix.
7. **Check yourself.** 3–5 questions that make the learner predict, decide or explain. Put answers
   in a collapsed block (`<details>` or `??? note` in MkDocs).
8. **Go deeper.** Curated resources, in three groups:
   - Official docs (1–3)
   - Articles and blog posts (2–3), from recognised authors or publications
   - Videos (1–3), YouTube or conference talks
9. **Used in.** The task, wave or phase that needs this chapter, and what the learner will do there.

## Resource verification (mandatory)

A syllabus with a dead or invented link teaches the learner to distrust it. Every resource must
be verified **in this session** before it is written:

- **Articles and docs:** fetch the URL, confirm HTTP 200 and that the page is about the topic.
  Use the page's real title.
- **YouTube:** query
  `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=<id>&format=json` and use
  the returned `title` and `author_name` exactly. Never write a video id you did not look up.
- **Prefer** official channels and well-known educators. Note length when known.
- Stamp the chapter footer: `Resources verified <YYYY-MM-DD>`.

If verification is not possible (no network), write the chapter without the Go-deeper list and
say so in the index. Never fill the gap from memory.

## Index page contents

- Scope sentence: what the syllabus covers and for which project.
- The level map table (technology, level, treatment: full / short / glossary / none).
- Reading order, with an estimated time per chapter (≈ 200 words per minute plus exercises).
- "How to use this": read a chapter when its task comes up; answer Check-yourself before moving
  on; briefs during build link back here.
- Chapter table: number, title, level, estimated time, used in.

## Quality checklist

- [ ] Every chapter is tied to at least one real task, wave or phase.
- [ ] Every chapter has a Mermaid diagram that shows a mechanism.
- [ ] Code examples use the project's stack and style, and actually compile or run.
- [ ] Every link and video was verified this session; nothing came from memory.
- [ ] No confidential source material is quoted. If the project has a confidentiality rule or
      checker, run it on the syllabus before committing.
- [ ] (c)/(d) technologies have no chapters. The level map decides, not completeness.

## Logging

After writing it:

```bash
specclaw-teach .specclaw <change> log brief "Syllabus generated: <n> chapters at <path>"
```

If no change exists yet (assessment run before propose), note it in the learning plan's
section 2 (Learn) instead, with a link to the syllabus index.
