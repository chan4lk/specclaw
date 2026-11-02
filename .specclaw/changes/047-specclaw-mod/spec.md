# Spec: specclaw mod

**Change:** 047-specclaw-mod
**Size:** architectural

## Functional Requirements

- **FR-1 State reader.** The mod reads `<cwd>/.specclaw/changes/<NNN>-<slug>/` (skipping `archive/`) through `$.fs`. Per change it derives: name, phase (`state.json` `.phase`), proposal status (`.phases.proposal.status`), verify verdict (`.phases.verify.verdict`), PR URL (`.pr` / `.phases.pr.url` when present), and task counts — `- [x]` / `- [ ]` / `- [!]`-style lines in `tasks.md`, else under `## Tasks` in a lean `change.md`. Unreadable or malformed files yield a change with unknown fields, never a thrown hook.
- **FR-2 Active set.** A change is *active* when it is not archived and its phase is not `archived`. The *current* change is the active change whose `state.json` is most recently modified.
- **FR-3 Changes pane.** `/specclaw-pane` opens pane `specclaw` titled `specclaw`. One row per active change: `NNN-slug  phase  done/total  [✗failed]  [verdict]  [PR]`. Empty state: `No active specclaw changes.`; no `.specclaw/`: `No .specclaw/ in this project.`
- **FR-4 Band.** Above the prompt, while a current change exists: `specclaw · <change> · <phase> · <done>/<total> tasks`. Otherwise the engine's own band (`next(e)`).
- **FR-5 Status line.** `specclaw: <n> active` plus ` · building <NNN>` when a change's phase is `build`; cleared when `.specclaw/` is absent.
- **FR-6 Refresh.** State is re-read at `session.start`, after every tool call whose input path or command mentions `.specclaw`, after each `turn.complete`, and when `/specclaw-pane` runs. Readings are stored in `$.state` so pane and band redraw.
- **FR-7 Propose gate.** On `Edit`, `Write`, `NotebookEdit`: when the target path resolves inside the session cwd, outside `<cwd>/.specclaw/` and outside `<cwd>/.git/`, the project has `.specclaw/`, and no active change has `proposal` status `approved` — the call is denied with: `specclaw: no approved change is open. Run /specclaw:propose and get approval before editing <relpath>.` Otherwise the call proceeds.
- **FR-8 Gate modes.** `userConfig.gate` ∈ `block` (default) | `warn` | `off`. `warn` lets the call run and shows a toast with the same text; `off` skips the check. A guard failure (thrown error) fails open with a toast, never blocks.
- **FR-9 Packaging.** `plugins/specclaw-mod` is listed in `.claude-plugin/marketplace.json`; every plugin is at one version (R1).

## Non-Functional Requirements

- **NFR-1** No new runtime dependency; the mod is TypeScript against the `claude-code` module only.
- **NFR-2** The mod writes nothing under `.specclaw/` — `specclaw-set-phase` stays the only phase writer.
- **NFR-3** Pure logic (parsing, active/current selection, gate decision, row formatting) lives in a module with no `$` dependency so it is unit-testable with `bun test` in CI without a Claude binary.
- **NFR-4** A project without `.specclaw/` sees no band, no status, no gate.

## Acceptance Criteria

- **AC-1** Given fixture changes with full (`tasks.md`) and lean (`change.md`) task lists, the reader returns correct phase, done/total/failed, verdict and PR per change, and skips `archive/`. (FR-1, FR-2)
- **AC-2** Malformed `state.json` yields a change with phase `?`, not an exception. (FR-1)
- **AC-3** The current change is the active change with the newest `state.json` mtime. (FR-2)
- **AC-4** Pane rows and band text render the formats in FR-3/FR-4, including both empty states. (FR-3, FR-4)
- **AC-5** Status text matches FR-5 with and without a change in `build`. (FR-5)
- **AC-6** Gate decision: deny for a source path with no approved change; allow with one approved change; allow for paths under `.specclaw/`, `.git/`, or outside cwd; allow when `.specclaw/` is absent. (FR-7, NFR-4)
- **AC-7** Gate modes: `warn` allows and returns the message for a toast; `off` allows silently. (FR-8)
- **AC-8** `claude plugin validate plugins/specclaw-mod` passes (run when `claude` is on PATH; skipped with a note otherwise). (FR-9)
- **AC-9** `marketplace.json` lists `specclaw-mod`, and all `plugin.json` + marketplace versions are equal. (FR-9)
- **AC-10** The new test runner is registered in `.github/workflows/ci.yml` and passes. (NFR-3)

## Edge Cases

- Change dir with no `state.json` (pre-plan) → phase `proposal`, status unknown → not counted as approved.
- `tasks.md` and `change.md` both present → `tasks.md` wins.
- `Write` to a not-yet-existing path → resolved by string against cwd; `..` segments normalised.
- Session cwd is a subdirectory of the repo → `.specclaw/` looked up at cwd only (v1); documented.
- Bash file writes are not gated (v1, by decision at approval).
