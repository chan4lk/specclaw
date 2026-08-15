# Proposal: Numbered change folders

**Created:** 2026-08-08
**Status:** 🟡 Draft

## Problem

`.specclaw/changes/` holds 30 change folders and none of them carry an ordering signal. `ls`, shell tab-completion, `.specclaw/STATUS.md`, and the GitHub file browser all sort alphabetically, so the only way to answer "which change came first?" is to open each `proposal.md` and read the `**Created:**` line.

Worse, the prefix that *looks* like it orders things doesn't. Archived folders use `YYYY-MM-DD-<slug>`, but that date is the **archive** date, not the creation date. Measured on this repo:

| Archive prefix | Real `**Created:**` span | Count |
|---|---|---|
| `2026-07-22-*` | 2026-03-28 → 2026-07-19 | 24 |
| `2026-07-21-*` | 2026-06-21 | 1 |
| `2026-07-25-*` | 2026-07-24 | 1 |

24 of 26 archived changes share one prefix from a single bulk-archive run, collapsing four months of history into one bucket. The prefix is not merely uninformative — it is actively misleading, because it reads as a creation date.

Active changes are worse still: `memory-aware-parallelism`, `phase-time-accounting`, `staged-files-auditor`, `tracker-state-integrity` carry no ordering hint at all.

This matters because specclaw's whole premise is a durable, on-disk record of how a project evolved. A record you cannot read in order is a weak record.

## Proposed Solution

Give every change a permanent, monotonically increasing number in its folder name: `.specclaw/changes/NNN-<slug>/` — `001-init-repo`, `002-auth-setup`, and so on. The number is assigned once at `/specclaw:propose` time and never changes, including through archival.

**Width is three digits.** Thirty numbers are already spoken for and this repo produced those thirty in about four months. Two digits would run out inside a year, and the overflow is silent rather than loud: `100-foo` sorts *before* `99-foo` lexically, which breaks every `ls`, tab-completion, and file-browser view — precisely the thing this change exists to fix. Three digits costs one character and the failure never arrives.

Five pieces:

1. **`specclaw-next-change-number <specclaw-dir>`** — new helper in `plugins/specclaw/bin/`. Globs both `changes/*/` and `changes/archive/*/`, extracts the leading `^[0-9]+` from each basename, prints `max + 1` zero-padded to three digits. Stateless: the number is *derived* from what is on disk, so there is no counter file to drift out of sync. This deliberately follows the same "one source of truth, no shadow state" principle as the recent phase-state work (#57).

2. **`/specclaw:propose` prefixes the slug.** `SKILL.md` step 1 becomes: slugify, then call `specclaw-next-change-number` and prepend. Single call site — the helper is the only place the numbering rule lives.

3. **Archive keeps the number, drops the date.** `archive/NNN-<slug>/` instead of `archive/YYYY-MM-DD-<slug>/`. The number already orders the folder, and the archive date is not lost — it stays in `status.md` and `state.json` where it belongs. This also keeps the max-scan in step 1 trivial, since active and archived names share one shape.

4. **Backfill is offered, never imposed.** `specclaw-renumber-changes <specclaw-dir>` reads `**Created:**` from each existing `proposal.md`, sorts ascending, assigns `001`…`030`, and `git mv`s each folder — falling back to the folder's first-commit date for the one change (`git-worktrees`) whose proposal has no `Created:` line. It is **dry-run by default** and requires `--apply` to touch the filesystem.

   Crucially, specclaw does not run this on its own. Renaming thirty folders in someone's repo is not a decision a tool gets to make silently, and a project that is happy with mixed numbering should stay that way. Instead:
   - `/specclaw:status` prints a single hint line when unnumbered folders exist — `26 unnumbered changes · run /specclaw:renumber to order them`. A hint, not a prompt.
   - `/specclaw:propose`, on the first run where it detects unnumbered folders, shows the dry-run plan and asks once whether to apply it. Decline and it proceeds with the new numbered change alone.
   - Either path ends in the user explicitly saying yes.

   No "already asked" flag is needed anywhere: the hint and the prompt are conditioned on unnumbered folders existing, so they self-clear the moment the backfill runs. Mixed numbering is a supported steady state, not an error — `specclaw-next-change-number` ignores non-numeric names when taking its max.

5. **Listing sorts numerically.** `specclaw-update-status` and `specclaw-reconcile` iterate `"$DIR"/*/` in glob order today; they sort numerically by prefix so STATUS.md reads in true chronological order, with unnumbered legacy folders grouped after the numbered ones.

The blast radius is small. An audit of every path-construction, glob, and state-write site found no regex or validation that restricts change names, and no code that assumes a name starts with a letter. Every listing site already uses `"$DIR"/*/` plus `basename`, which handles a numeric prefix unchanged. Branch names (`specclaw/NN-slug`) remain valid git refs; `state.json` stores the change name as an opaque string and is already tested against names containing sed metacharacters.

## Scope

### In Scope
- New `specclaw-next-change-number` helper — derives next number by scanning active + archive, three-digit zero-padded, ignores non-numeric names.
- `/specclaw:propose` — prefix new change folders with the number.
- `/specclaw:archive` — archive as `NNN-<slug>`, dropping the date prefix.
- New `specclaw-renumber-changes` backfill tool with dry-run default, covering both active and archived folders.
- `/specclaw:renumber` skill wrapping that tool, so the backfill has a name the user can be pointed at.
- Unnumbered-folder detection: a hint line in `/specclaw:status`, a one-time offer in `/specclaw:propose`. Both self-clearing.
- Numeric-prefix-aware ordering in `specclaw-update-status` and `specclaw-reconcile`.
- Tests: number derivation with gaps, with an empty `changes/`, with unnumbered legacy folders present, across the active/archive boundary, and at the 99→100 boundary.
- Docs: README / skill descriptions that show a `changes/<name>/` path.

### Out of Scope
- **Automatic backfill.** The tool never renames without an explicit yes. See solution item 4.
- **Renaming git branches or PR titles for already-shipped changes.** Those are historical artifacts; `state.json` records the branch that was actually used, and rewriting them buys nothing.
- **Retitling closed GitHub issues.** Same reasoning.
- **Closing gaps.** If a change folder is deleted, its number retires with it. Numbers are identifiers, not indices.
- **A config knob for the numbering format.** Three digits, one rule, no options.
- **Renumbering to reflect completion order rather than creation order.** Creation order is what "which came first" means here.

## Impact

- **Files affected:** ~11 (estimated) — 2 new `bin/` scripts, 1 new skill, 3 skill markdowns, 2 existing `bin/` scripts, 1–2 test files, docs. Folder renames happen only if a user opts into the backfill.
- **Complexity:** medium (small change, wide-but-shallow rename)
- **Risk:** low going forward, medium at backfill time

The going-forward rule is near-zero risk: it changes one string at one call site, and mixed numbered/unnumbered folders are a supported state.

The risk lives in the backfill, and only for users who choose to run it. Renaming 30 folders touches paths referenced by `.specclaw/STATUS.md` and by each change's `state.json`. Mitigations: dry-run is the default and prints every planned `git mv`; nothing renames without an explicit yes; the backfill refuses to run while any change is mid-build, since a live worktree or branch would still point at the old path; and `specclaw-reconcile` already exists to detect and repair exactly this class of drift afterward.

## Decisions Taken

1. **Width: three digits** (`001-init-repo`). Settled — see the rationale under Proposed Solution.
2. **Backfill is user-initiated.** specclaw surfaces that unnumbered folders exist and offers the dry-run plan; the user says yes or ignores it. Existing repos are never rewritten on an upgrade.

## Open Questions

1. **Is the folder name the change's identity, or is `state.json`'s `"change"` field?** They are equal today. The backfill must update both in lockstep, or `specclaw-reconcile` will flag every renamed change as drifted. Planning should confirm there is no third place the name is persisted.

2. **Should the `/specclaw:propose` offer fire on every unnumbered repo, or only when the count is small enough to be uncontroversial?** A user with 200 legacy folders may find the offer more alarming than helpful. Leaning toward: always offer, since it is one declinable line and the dry-run makes the scope visible before anything moves.

3. **This proposal's own folder is unnumbered.** Left that way deliberately — the backfill will assign it its number, which doubles as the first end-to-end test of the tool.

---

**To proceed:** Review this proposal and approve to begin planning.
