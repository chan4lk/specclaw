# Spec: Core records + plugin suggestions at the moment of need

**Change:** 059-core-records-suggest
**Size:** bounded

## Requirements

- **FR-1:** `specclaw-suggest <specclaw_dir> <feature>` prints one line,
  `Tip: <what it adds>. Install: /plugin install <plugin>@chan4lk (say "no" to never see this again)`,
  for the features `review`, `fleet`, `sync`, `bf` (and `extras`, which the hook uses). `dash` is deferred to 062, which ships the `specclaw-dash` plugin: a tip must never name a plugin that does not exist. It prints it only when the feature's plugin is
  not installed and the feature is not in `plugins.dismissed` in `<specclaw_dir>/config.yaml`.
  Otherwise it prints nothing.
- **FR-2:** `specclaw-suggest <specclaw_dir> --dismiss <feature>` adds the feature to `plugins.dismissed`
  once. It creates the `plugins:` block when the config has none.
- **FR-3:** `specclaw-suggest` always exits 0 and never writes to stderr in suggest mode. An unknown feature,
  a missing config or a Codex host prints nothing.
- **FR-4:** Codex is detected by the variables Codex sets in its shell tool environment (`CODEX_THREAD_ID`,
  `CODEX_SANDBOX`). The repo had no runtime host check before: changes 040 and 048 only split manifests.
- **FR-5:** The feature table and the install check (`installed`, `missing`) live in one sourced helper,
  `lib/plugins.sh`. `hooks/session-start` and `specclaw-suggest` both source it. The hook's notices also honour
  `plugins.dismissed`; otherwise its output does not change.
- **FR-6:** Skills call `specclaw-suggest` at the proposal's call sites, minus `dash` (062): verify (`review`, replacing
  the silent skip), status (`fleet` when 2+ approved changes are not built), propose (`sync` when the
  idea names an issue, work item or PR), init (`bf` on an existing codebase). Each shows a tip at most once per
  session per feature, and a "no" runs `--dismiss`.
- **FR-7:** `specclaw-log-learning` log mode also appends one line to `changes/<change>/timeline.jsonl`:
  `{"kind":"lesson","at":"<ISO>","category","priority","detail","action"}`. `learnings.md` is unchanged.
  The line has no `ev` and no `ts`, so elapsed time in `update-status` is not affected. `specclaw-timer`
  skips `lesson` lines without counting them as unparseable.
- **FR-8:** `templates/config.yaml` carries `plugins: dismissed: []`.

## Acceptance Criteria

- **AC-1:** Missing plugin, not dismissed → the exact tip line for that feature; exit 0.
- **AC-2:** Installed plugin (on PATH, or next to core in the plugin cache) → no output; exit 0.
- **AC-3:** Dismissed feature → no output. `--dismiss` is idempotent, creates the block when absent, and leaves a hand-written block list untouched.
- **AC-4:** Unknown feature, missing config, or `CODEX_THREAD_ID` set → no output; exit 0.
- **AC-5:** `session-start` sources `lib/plugins.sh`, drops a dismissed feature's notice, and `run-plugin-split-tests.sh` and `run-bootstrap-hook-tests.sh` still pass.
- **AC-6:** `specclaw-log-learning` appends one valid JSON `lesson` line with the given fields, and `specclaw-timer report` prints no "unparseable" warning for it.
- **AC-7:** The skill call sites name `specclaw-suggest`; verify no longer says "skip silently" for the missing review plugin; the lean skills stay within the 300-word cap.

## Approach

One decision: suggestions are a stateless script plus the existing config file. "Once per session" is held by
the agent, not a state file. The install check moves, it is not copied.

File map:
- `plugins/specclaw/lib/plugins.sh` (new): `installed`, `missing`, from `hooks/session-start`
- `plugins/specclaw/bin/specclaw-suggest` (new); `plugins/specclaw/hooks/session-start` sources the lib
- `plugins/specclaw/bin/specclaw-log-learning`, `plugins/specclaw/bin/specclaw-timer` (skip `lesson` lines)
- `plugins/specclaw/skills/{verify,status,propose,init}/SKILL.md`, `references/full/{verify,status,propose,init}.md`
- `plugins/specclaw/templates/config.yaml`; tests `run-suggest-tests.sh` + `ci.yml`; `plugins/specclaw/CLAUDE.md`
