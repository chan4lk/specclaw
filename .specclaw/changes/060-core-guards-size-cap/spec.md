# Spec: Core guards (branch, done) and the PR size cap

**Change:** 060-core-guards-size-cap
**Size:** bounded

## Requirements

- **FR-1 (branch guard):** the mod's propose gate also holds an `Edit`, `Write` or `NotebookEdit` on a project file
  outside `.specclaw/` and `.git/` while the session's checkout is on the base branch, with the message
  `specclaw: <branch> is the base branch. Create a change branch first before editing <file>.` It follows the
  gate's modes (`warn` toast, `block` deny, `off` none) and holds even when a change is approved. The base branch
  is `git.base_branch` from `.specclaw/config.yaml`, else `origin/HEAD`, else `main` (change 020's order, without
  the network `gh` step). No git, a detached HEAD or a git error skips the branch check.
- **FR-2 (done guard):** `plugins/specclaw/hooks/done-guard` is a `Stop` command hook. For each active change touched
  since the merge-base with the base branch (committed, uncommitted or untracked under `.specclaw/changes/<name>/`)
  whose tasks are all done (`specclaw-parse-tasks --count`: done + deferred = total > 0), it names each missing step:
  - the verify verdict is missing or not PASS (`state.json` `phases.verify`);
  - code outside `.specclaw/` was committed after the verify verdict, or the working tree has uncommitted or
    untracked changes outside `.specclaw/` (it is not for HEAD); a verdict with no time is held too;
  - when `specclaw-review` is on PATH, `specclaw-review verdict --change <name>` exits non-zero.
  It prints them on stderr and exits 2. It exits 0 when nothing is missing, when the input has
  `"stop_hook_active": true`, when there is no `.specclaw/config.yaml`, and on any internal error, which it names in a `systemMessage`. A change it cannot check goes only through
  `skip(change, reason)`, which always names the change and the reason to the user and still exits 0.
  Without a resolvable base it checks every active change (never fewer).
- **FR-3 (registration):** Claude Code registers the done guard from `hooks/mod.json` (the file only the Claude
  manifest names). `hooks/hooks.json`, which Codex reads, stays unchanged: nothing in the repo shows Codex accepts
  a `Stop` command hook (change 048 proved only `SessionStart` and the `description`/`hooks` keys).
- **FR-4 (size cap):** `specclaw-verify size <specclaw_dir> <change>` counts production lines (added + deleted)
  between the merge-base with the base branch and the working tree, plus untracked files. It leaves out tests (ignoring case: `test/`, `tests/`, `spec/`, `specs/`, `*.spec.*`, `*_spec.*`,
  `*.test.*`, `*_test.*`; and CamelCase `*Test.*`, `*Tests.*` by their capital T),
  `.specclaw/`, lockfiles and generated files, plus any git glob pathspecs in `pr.size_exclude` (space-separated).
  Over `pr.size_cap` (default 400; `0` = off) it exits 1, unless the change's `proposal.md` has a
  `Size waiver: <reason>` line; then it exits 0 naming the waiver. Over half the cap it prints a
  "consider splitting" note. When it cannot count (no base branch, or git fails) it says so and exits 2, which
  verify records as a FAIL, never as under the cap.
- **FR-5:** the verify flow (lean and full) runs `specclaw-verify size`; exit 1 is a FAIL.

## Acceptance Criteria

- **AC-1:** `gate.spec.ts`: on the base branch, a project file edit is held (`deny` in block, `warn` in warn, allowed in
  off) even with an approved change; `.specclaw/` and `.git/` edits and edits on another branch are not held by it.
- **AC-2:** a kit test drives the real mod: on `main` with an approved change, a `Write` in block mode is denied with
  the branch message; on a change branch it runs; a failing `git` call does not deny.
- **AC-3:** `run-done-guard-tests.sh`: exit 2 naming the step for a touched, all-done change with no verify, a FAIL
  verify, code committed after verify, or a non-clean review stub; exit 0 for a PASS-at-HEAD change, an untouched
  change, a change with open tasks, `stop_hook_active: true`, no config, and a broken environment.
- **AC-4:** `run-size-cap-tests.sh`: excluded paths are not counted, untracked files are, over the cap exits 1, a
  waiver exits 0, no base exits 2, over half prints the split note, `pr.size_cap: 0` is off, `pr.size_exclude` is honoured.
- **AC-5:** `run-codex-plugin-tests.sh` passes with `hooks/hooks.json` unchanged and checks `mod.json` still loads
  `./register.tsx`; `run-mod-tests.sh` (bun, `claude plugin validate`, `claude plugin test`) passes.
- **AC-6:** `MOD.md`, `plugins/specclaw/CLAUDE.md`, the verify skill and reference, and the config template describe
  the three guards; the new suites are registered in CI.

## Approach

One decision: keep each guard on the path that already owns its concern. The branch check goes into the existing
pure `gateDecision`, the done guard is a plain bash command hook registered only for Claude Code, and the size count
is a new `specclaw-verify` subcommand. Base-branch resolution is one shared helper.

File map:
- `plugins/specclaw/hooks/core/gate.ts`, `plugins/specclaw/hooks/branch.ts` (new), `plugins/specclaw/hooks/register.tsx` — branch guard
- `plugins/specclaw/hooks/done-guard` (new), `plugins/specclaw/hooks/mod.json` — done guard
- `plugins/specclaw/lib/base-ref.sh` (new), `plugins/specclaw/bin/specclaw-verify`, `plugins/specclaw/templates/config.yaml` — size cap
- tests: `plugins/specclaw/tests/gate.spec.ts`, `branch.test.ts` (new), `run-done-guard-tests.sh` (new), `run-size-cap-tests.sh` (new), `run-codex-plugin-tests.sh`, `.github/workflows/ci.yml`
- docs: `plugins/specclaw/MOD.md`, `plugins/specclaw/CLAUDE.md`, `plugins/specclaw/skills/verify/SKILL.md`, `plugins/specclaw/references/full/verify.md`
