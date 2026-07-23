# Design: lifecycle-bug-fixes

**Change:** lifecycle-bug-fixes
**Created:** 2026-06-14

## Technical Approach

Each bug is a localized defect in one `bin/` script (plus the propose skill/template for B6). Fix
each at its root, reusing patterns already present in the repo (the portable `sedi()` wrapper in
`specclaw-pr`, the awk task-id extraction in `specclaw-parse-tasks`). Add one plain-bash regression
script with fixtures so the template→parser contract is checkable going forward — no test framework
is introduced (none exists today; Rule 2 simplicity).

## Architecture

All scripts live in `plugins/specclaw/bin/`. The three "parsers" that must agree on the same
template output:
- `specclaw-parse-tasks` — **reference impl** (awk; requires `` `T[0-9]+` ``, tracks fences). Not
  modified — it is the contract the others are aligned to.
- `specclaw-validate-change` — fixed to match it (FR1).
- `specclaw-verify collect` — fixed for AC/Files tolerance (FR2, FR3).

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-validate-change` | modify | B2: `count_incomplete`/`count_total`/`count_tasks` require `` `T[0-9]+` `` and skip fenced blocks |
| `plugins/specclaw/bin/specclaw-verify` | modify | B3: AC grep accepts `AC1`/`AC-1`, optional checkbox/bold. B4: `Files:` grep allows leading `- `/`* `. B6: `update-status` creates `status.md` if absent |
| `plugins/specclaw/bin/specclaw-verify-context` | modify | B5: replace bare `sed -i` calls with portable `sedi()` (or awk); no path in script position |
| `plugins/specclaw/bin/specclaw-azdo-pr` | modify | B7: `build_pr_title` from `# Proposal:` H1. B8: `adoapi_post` captures `%{http_code}`+body, prints ADO error on non-2xx |
| `plugins/specclaw/bin/specclaw-pr` | modify | B7: `build_pr_title` from `# Proposal:` H1 (same fix as azdo) |
| `plugins/specclaw/bin/specclaw-build` | modify | B9: `finalize` captures `git checkout` stderr into the error message |
| `plugins/specclaw/skills/propose/SKILL.md` | modify | B6: instruct propose to scaffold `status.md` from template |
| `plugins/specclaw/bin/specclaw-ensure-init` *or* propose flow | verify | Ensure a per-change `status.md` is created (whichever owns scaffolding) |
| `plugins/specclaw/tests/run-parser-tests.sh` | create | Regression suite + fixtures (AC-9) |
| `plugins/specclaw/tests/fixtures/*` | create | Sample `tasks.md`/`spec.md` matching template output |

## Data Model Changes

None. Output JSON shapes (`acceptance_criteria`, `changed_files`) are unchanged — only populated
correctly.

## API Changes

- `adoapi_post` (B8): on non-2xx, prints `ADO HTTP <code>: <body>` to stderr and returns non-zero.
  Callers already `die` on empty parse, so behavior on success is unchanged; failure is now loud.
- `build_pr_title` (B7): same signature, different source line. Falls back to `[specclaw] <change>`
  when no `# Proposal:` H1 exists (unchanged fallback path).

## Key Decisions

1. **Align to `parse-tasks`, don't rewrite it.** `parse-tasks` already does the right thing
   (backtick `T\d+`, fence tracking). `validate-change` is brought to the same rule rather than
   inventing a third behavior. (B2)
2. **Make collectors tolerant, not the templates rigid.** Rather than forcing one AC/Files format,
   the collector accepts the variants the planner naturally emits. This fixes the *systemic* silent
   degradation (B3/B4) regardless of which format a given plan used.
3. **B6 — fix both sides.** Scaffold `status.md` in `propose` (fixes all future changes) *and*
   self-heal in `update-status` (fixes existing changes / direct invocations). Per the resolved
   open question.
4. **B7 in-place in both scripts.** Two call sites only → no shared library; surgical edits.
5. **Reuse `sedi()` for B5.** The portable wrapper already exists in `specclaw-pr`; copy it (or
   rewrite the two strip steps in awk) rather than add a dependency.
6. **Plain-bash tests.** A single executable script with fixture files; no bats/npm. Asserts the
   three parsers agree on template-shaped input and that the existing in-repo specs still parse.

## Risks & Mitigations

- **R1: Parser change breaks existing valid docs.** Mitigation: NFR2 + AC-9 run the in-repo
  `build-engine` spec/tasks through the fixed parsers; both formats must pass.
- **R2: B5 awk/sed rewrite changes the extracted template subtly.** Mitigation: diff the produced
  payload before/after on the same `agent-prompts.md`; AC-4 asserts non-empty + no sed error.
- **R3: B8 change alters success path.** Mitigation: only the non-2xx branch is new; 2xx returns
  the body exactly as before.
- **R4: B6 status.md format drift.** Mitigation: scaffold from `templates/status.md` (single
  source) in both the propose and self-heal paths.
