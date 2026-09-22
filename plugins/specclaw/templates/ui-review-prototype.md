# UI Review: {{change}}

**Date generated:** {{date}}
**Backlog item:** {{bl_item}}
**UI fidelity policy:** REINTERPRET (SQ-013)
**Built in:** {{stack}}
**Screens in scope:** {{screen_count}} · **Rows needing a signature:** {{row_count}}

<!--
  NOTE ON THIS COMMENT: never write a literal double-brace placeholder
  token inside this comment's own prose — filling this template is a dumb
  global string replace and would corrupt the comment.

  THE REINTERPRET VARIANT. Under FAITHFUL and THEME-ONLY the reference is a
  screenshot of the LEGACY application, and the question is how closely the
  rebuild reproduces it. Under REINTERPRET there is no such question: the
  legacy interface is reference material only, and reproducing it is
  explicitly not required.

  So the reference here is the APPROVED PROTOTYPE SCREEN — the design a
  named client stakeholder signed off, by name and date, before any of this
  application was built. The question each row asks is whether the built
  screen does what the approved design said it would.

  THIS FILE IS EVIDENCE, NOT A COMPUTED VERDICT. Nothing in it is a
  pass/fail produced by specclaw. Every row is a question put to a named
  human, and it is only answered when that human types their name and the
  date into it. An unsigned row is an open question; an unsigned file
  proves nothing at all. That is the same rule the FAITHFUL/THEME-ONLY
  review follows, for the same reason: UI stays excluded from the
  golden-master seam taxonomy, no fixture compares a screenshot, and
  specclaw never claims pixel-identity.

  WHERE THE ROWS COME FROM: each is a review point recorded in
  prototype-manifest.json when the prototype was briefed, naming the
  DR-### or workflow step it protects. They are carried in the manifest
  precisely so this repo needs nothing from the prototype brief, which is
  never copied here — and the prototype application itself is never copied
  here either.

  WHAT TO DO WITH IT: complete every row, then commit this file with the
  change's PR, alongside the replay evidence package.
-->

## How to complete this review

1. Open the approved prototype screenshot referenced for each screen below. Its sha256 is recorded so you can confirm you are looking at the same file the approver signed off — if the hash no longer matches, the evidence changed and this review is void.
2. Open the same screen in the rebuilt application.
3. For each row, decide whether the built screen satisfies the statement, then fill in **Verified by** (your name), **Date** (YYYY-MM-DD), and **Notes** (required whenever the row is not satisfied — say what differs).
4. Commit the completed file with the PR.

**This is not a pixel comparison.** The rows ask whether the built screen behaves and reads the way the approved design said it would. A difference that does not break a row is not a finding.

## Screens

{{review_sections}}

## Screens Without Recorded Evidence

<!--
  Screens this change touches whose approved prototype screenshot is
  absent from the manifest, or whose recorded hash does not match the file
  on disk. A reviewer cannot complete those rows — there is nothing
  trustworthy to compare against.
-->

{{missing_evidence}}

---

_This review is complete only when every row above carries a name and a date. specclaw does not, and cannot, complete it._
