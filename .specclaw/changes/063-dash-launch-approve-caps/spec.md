# Spec: specclaw-dash actions — launch fleet runs, approve lessons, edit context caps, undo dismissals

**Change:** 063-dash-launch-approve-caps
**Size:** bounded
**Depends on:** 062-dash-pane (the pane), 059 (`plugins.dismissed`), 065 (`specclaw-budget`, built in parallel)

## Open question answered: can a mod pane run a command?

**Yes.** On Claude Code 2.1.325 a pane's `Button` has `onPress` and an `Input` has `onSubmit`, and from those
a mod can call `$.process.run` (a raw host process), `$.command.run` (a slash command) or `$.tool.call`
(a tool, through the session's permission check). It can also fill the prompt with `$.prompt.fill`.

- **D-1 Every action runs through the Bash tool, `$.tool.call({ tool: 'Bash' })`.** Not `$.process.run`: the
  Claude Code process starts without plugin `bin/` folders on its `PATH` (they are added per Bash call), so
  `specclaw-fleet`, `specclaw-review`, `specclaw-suggest` and `specclaw-budget` resolve only in the Bash tool.
  The Bash tool also keeps the session's permission rules in charge: the pane can run nothing a rule denies.
- **D-2 Fallback.** When the permission check refuses the call (`{ deny }`, for example a default-mode session
  with no allow rule), the pane puts the exact command into the prompt (`$.prompt.fill`) and says to send it.
- **D-3 Two missing commands are added, nothing else.** No CLI can reject a proposed rule or undo a dismissal,
  so `specclaw-review learn --reject <fp>...` and `specclaw-suggest <dir> --dismissed` / `--undismiss <f>`
  are added. The pane owns no logic: it maps a press to one command string and shows the output.
- **D-4 Consent.** Launch first runs `specclaw-fleet optin <items> --dry-run`. Confirm is offered only for the
  items the dry-run says will be (or already are) assigned to and tagged `fleet:auto` by the identity behind
  the user's own `AZDO_TOKEN`; an item assigned to someone else is refused by `optin` and never launched. Confirm
  then runs `optin` for real and `trigger` (or `feature start`), which re-checks consent itself.

## Functional requirements

- **FR-1 Launch.** An ACTIONS part of `/dash` lists approved changes (proposal approved, phase before build, no
  PR) and the `**Feature:**` modules of active changes, each a toggle. **Dry run** runs
  `specclaw-fleet optin <selected...> --dry-run` and shows its lines. **Confirm launch** appears only after a
  dry run of exactly the current selection, names how many items it launches and that it spends the user's plan
  and pushes a branch, and runs `specclaw-fleet optin <ok...> && specclaw-fleet trigger <change> && ... &&
  specclaw-fleet feature start <module>` for the launchable items only. Changing the selection drops the plan.
- **FR-2 Fleet missing.** `specclaw-fleet` not found (exit 127) shows how to install and set it up
  (`/plugin install specclaw-fleet@chan4lk`, then `/specclaw-fleet:setup`); a dry run that names no item (fleet
  not configured, no token) shows its first line and `/specclaw-fleet:setup`. Neither offers Confirm.
- **FR-3 Approve lessons.** Each rule `learn_propose` lists has **Approve** (`specclaw-review learn --apply
  <fp>`) and **Reject** (`specclaw-review learn --reject <fp>`). A rejected lesson is no longer proposed but
  stays in review memory for recall.
- **FR-4 Caps.** **Show caps** runs `specclaw-budget roles --json <specclaw_dir>` and lists each role's
  context cap, range, default and source, with an input per role; Enter runs `specclaw-budget set
  <specclaw_dir> <role> <n>` and reloads. The pane never writes `config.yaml` itself. `specclaw-budget` not
  found shows one line, `Caps need specclaw ≥ the context-gate release (065): specclaw-budget is not installed.`, and no controls.
- **FR-5 Dismissed suggestions.** **Show dismissed** runs `specclaw-suggest <specclaw_dir> --dismissed` and
  lists each feature with **Undo** (`specclaw-suggest <specclaw_dir> --undismiss <feature>`).
- **FR-6 Safety.** Every value put into a command (change, module, fingerprint, role, number, feature) must
  match a fixed pattern or the action is refused. The mod still calls no `$.process` and only the read methods
  of `$.fs`. After each action the pane shows the command, its exit code and its output, then refreshes.
- **FR-7 Claude Code only.** The dash stays out of `.agents/plugins/marketplace.json`; its Codex manifest stays
  metadata only.

## Acceptance criteria

- **AC-1** Each action maps to exactly the command in FR-1..FR-5 (bun specs over the pure mapping).
- **AC-2** A value that fails its pattern is refused before any command is built.
- **AC-3** Confirm launch is absent before a dry run, after the selection changes, and when no item is
  launchable; it launches only the items the dry run did not refuse (kit test).
- **AC-4** A denied Bash call fills the prompt with the exact command (kit test).
- **AC-5** Approve, Reject, caps set and Undo run their commands (kit test); `specclaw-budget` missing shows the
  065 note and no input.
- **AC-6** `specclaw-review learn --reject` stops proposing the lesson and keeps it in `memory query`.
- **AC-7** `specclaw-suggest --dismissed` prints the list; `--undismiss` removes one feature and keeps the rest.
- **AC-8** The mod calls no `$.process`, only `$.fs` exists/read/list/stat, and `$.tool.call` only in
  `hooks/act.ts`; `claude plugin validate` and `claude plugin test` pass; the plugin-split AC-7 still passes.

## Approach

One pure module `hooks/core/actions.ts` builds every command string from validated values and parses the
dry-run, the caps JSON and the dismissed list; one runner `hooks/act.ts` is the only `$.tool.call` (Bash, with
the prompt fallback). `register.tsx` draws the ACTIONS part with Buttons and Inputs and keeps the selection,
plan and last result in one atom.
Files: plugins/specclaw-dash/{hooks/core/actions.ts, hooks/act.ts, hooks/register.tsx, hooks/read.ts,
hooks/core/loops.ts, hooks/core/view.ts, types/index.d.ts, tests/*, README.md, .claude-plugin/plugin.json,
.codex-plugin/plugin.json}; plugins/specclaw-review/{bin/specclaw-review, lib/review_core.py,
lib/review_memory.py, tests/run-review-tests.sh}; plugins/specclaw/{bin/specclaw-suggest, lib/plugins.sh,
tests/run-suggest-tests.sh}; README.md and .claude-plugin/marketplace.json (the dash's description); version files.
