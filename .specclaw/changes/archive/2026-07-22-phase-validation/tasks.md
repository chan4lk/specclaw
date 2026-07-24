# Tasks: Phase Validation Guards

**Change:** phase-validation
**Created:** 2026-03-28
**Total Tasks:** 2

## Tasks

### Wave 1

- [x] `T1` — Create validate-change.sh
  - Files: skill/scripts/validate-change.sh
  - Estimate: small
  - Notes: Arguments: <specclaw_dir> <change_name> <phase>. Phases: propose (just check change dir can be created), plan (proposal.md exists), build (spec.md + design.md + tasks.md exist), verify (all tasks complete — no [ ] or [~] or [!] in tasks.md, only [x]), archive (verify-report.md exists with verdict), github-create (proposal.md exists). Read config.yaml workflow.strict (default true). If strict is false, output warnings but exit 0. If strict is true, exit 1 on failures. List ALL missing prerequisites, not just the first. Include --help. Also add a `status` subcommand that shows current phase of a change (which artifacts exist).

### Wave 2

- [x] `T2` — Hook validation into SKILL.md commands and add config option
  - Files: skill/SKILL.md, skill/templates/config.yaml
  - Depends: T1
  - Estimate: small
  - Notes: At the start of each command section (plan, build, verify, archive), add step 0: "Run validate-change.sh .specclaw <change> <phase>. If it fails, stop and report missing prerequisites to the user." Also hook into gh-sync create call. Add workflow.strict to config template (default true, with comment explaining it can be disabled for rapid prototyping). Keep changes minimal — one line per command section.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
