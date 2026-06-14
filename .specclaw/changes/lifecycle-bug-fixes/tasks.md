# Tasks: lifecycle-bug-fixes

**Change:** lifecycle-bug-fixes
**Created:** 2026-06-14
**Total Tasks:** 8

## Summary

Fix 8 lifecycle bugs (B2–B9). Wave 1 fixes each script independently (no shared files). Wave 2
adds the regression suite that locks the template→parser contract. B1 is parked (out of scope).

## Tasks

### Wave 1 — Root-cause fixes (independent files, parallel)

- [x] `T1` — B2: validate-change counts only real tasks, ignores fenced blocks
  - Files: `plugins/specclaw/bin/specclaw-validate-change`
  - Estimate: small
  - Notes: In `count_incomplete`/`count_total`/`count_tasks`, require a backtick-wrapped
    `` `T[0-9]+` `` id and skip lines inside ``` fences, matching `specclaw-parse-tasks`
    (awk fence-tracking + `match($0,/\`T[0-9]+\`/)`). AC-1.

- [x] `T2` — B3+B4+B6: verify collect AC/Files tolerance + update-status self-heal
  - Files: `plugins/specclaw/bin/specclaw-verify`
  - Estimate: medium
  - Notes: B3 — AC grep accepts `AC1`/`AC-1`, optional `- [ ]` checkbox and optional `**`; fix the
    clean-up sed for the no-checkbox case. B4 — `Files:` grep allows an optional leading `- `/`* `
    bullet. B6 — in `update-status`, if `status.md` is absent, create it from
    `templates/status.md` instead of `die`. AC-2, AC-3, AC-5 (self-heal half).

- [x] `T3` — B5: verify-context portable sed (no path in script position)
  - Files: `plugins/specclaw/bin/specclaw-verify-context`
  - Estimate: small
  - Notes: Replace bare `sed -i '…' "$TEMPLATE_FILE"` calls (lines ~225–232) with the portable
    `sedi()` wrapper from `specclaw-pr` (or rewrite the blank-line/fence strips in awk). AC-4.

- [x] `T4` — B6: scaffold per-change status.md in propose
  - Files: `plugins/specclaw/skills/propose/SKILL.md`
  - Estimate: small
  - Notes: Add a step that writes `status.md` from `$CLAUDE_PLUGIN_ROOT/templates/status.md` when
    creating the change dir, so every future change has one. AC-5 (scaffold half).

- [x] `T5` — B7+B8: azdo-pr title from H1 + surface ADO errors
  - Files: `plugins/specclaw/bin/specclaw-azdo-pr`
  - Estimate: medium
  - Notes: B7 — `build_pr_title` reads the `# Proposal:` H1 line, strips the `# Proposal: ` prefix,
    removes markdown/newlines, keeps the 128-char ellipsis cap; fall back to `[specclaw] <change>`.
    B8 — `adoapi_post` captures `%{http_code}` + body, prints `ADO HTTP <code>: <body>` to stderr
    and returns non-zero on non-2xx. AC-6 (azdo), AC-7.

- [x] `T6` — B7: gh specclaw-pr title from H1
  - Files: `plugins/specclaw/bin/specclaw-pr`
  - Estimate: small
  - Notes: Same `build_pr_title` fix as T5, 72-char cap unchanged. AC-6 (gh).

- [x] `T7` — B9: build finalize surfaces git checkout stderr
  - Files: `plugins/specclaw/bin/specclaw-build`
  - Estimate: small
  - Notes: In `cmd_finalize`, capture stderr of `git checkout "$main_branch"` and append it to the
    `errors+=("Failed to checkout … for merge")` message. AC-8.

### Wave 2 — Regression suite

- [x] `T8` — Parser-contract regression tests + fixtures
  - Files: `plugins/specclaw/tests/run-parser-tests.sh`, `plugins/specclaw/tests/fixtures/`
  - Estimate: medium
  - Depends: T1, T2
  - Notes: Plain-bash script (no framework). Fixtures = template-shaped `tasks.md` (with Legend
    fence) and `spec.md` (both AC formats). Assert: `parse-tasks` and `validate-change` agree on
    task counts; `verify collect` returns the expected ACs + files; the in-repo `build-engine`
    spec/tasks still parse (NFR2). Single command runs all. AC-9.

---

## Legend

Status markers: pending, in-progress (`~`), complete (`x`), failed (`!`).

Each task line is `` `T<id>` — <title> `` followed by indented `Files:` / `Estimate:` /
`Depends:` / `Notes:` detail lines.
