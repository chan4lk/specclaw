# Verify report: 045-project-custom-presets

**Verdict:** PASS. All 7 ACs are met at 09eca6b. The local review loop did not reach a clean final pass (see Review below). The operator chose to ship with 2 open majors recorded as follow-ups.

## Acceptance criteria

| AC | Result | Evidence |
|----|--------|----------|
| AC-1 no local dir: built-in base then dotnet, exit 0 | MET | `run-preset-check-tests.sh` AC-1 |
| AC-2 local `dotnet.md` replaces the built-in | MET | AC-2 |
| AC-3 frontmatter `extends: dotnet`: built-in then local | MET | AC-3, plus the `fm:` variant rows |
| AC-4 local `acme` printed; unknown `nope` warns, exit 1 | MET | AC-4 |
| AC-5 path-like names are unknown, exit 1 | MET | AC-5, plus the "path-like names" and symlink rows |
| AC-6 init scaffolds `.specclaw/presets/README.md` | MET | AC-6 runs a fresh init and `cmp`s the README against the template |
| AC-7 lean build reads presets through `specclaw-presets` | MET | AC-7 |

## Commands run (macOS, 09eca6b)

- `bash plugins/specclaw/tests/run-preset-check-tests.sh`: exit 0, 66 PASS.
  - Includes table-driven variants for each `presets:` form, frontmatter, stray `extends:`, symlink, dangling and directory refusals, and nested extends.
- `run-lean-flow`, `run-plugin-split`, `run-codex-skill` and `run-description-lint`: all exit 0.
- `shellcheck-gate.sh`: no new findings.
- The 5 macOS-only suite failures exist on main and are fixed separately in PR #100. They are unrelated to this change.

## Design changes since plan (operator decisions)

- `extends` is read only from leading frontmatter (`---` / `extends: <name>` / `---`). Line-based detection escalated in review rounds 3 and 4.
- An `extends:` line outside frontmatter only warns. It never fails a build (round 5 escalation).
- A dangling symlink, a directory, or an out-of-dir symlink named `<name>.md` is refused, with no fallback to the built-in. Nested extends is reported. A local parent that extends its own built-in is allowed.

## Screenshots

None. This change has no UI.

**Code Review:** APPROVED_WITH_NOTES. 0 BLOCK, 2 WARN, 1 NOTE at the first build (see `review-report.md`). Both WARNs (YAML forms, symlink escape) were fixed in review rounds 1 and 2.
**Review loop:** Review: ESCALATE — 10 rounds, final pass missing, models sonnet/opus; last round 0/3/6 b/M/m. The operator deferred the 2 remaining majors (one shared scalar parser; tab-led comments) to `follow-ups.md`.
