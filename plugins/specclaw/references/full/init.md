
# specclaw init

Initialize SpecClaw in the current project.

1. Run `specclaw-init . [project_name] [project_description]`. This creates `.specclaw/` with `config.yaml` (from template), `STATUS.md`, and `changes/archive/`.
2. Ask the user for project name and description if not supplied.
3. Suggest adding `.specclaw/` to git tracking.
4. If the repo already had code before init (commits or source files), run `specclaw-suggest .specclaw bf` and show any line it prints, at most once per session; if the user says no, run `specclaw-suggest .specclaw --dismiss bf`.

If `.specclaw/` already exists, the script exits with an error — do not overwrite.

**Full flow:** `specclaw-init` writes `flow: lean`. For the full proposal/spec/design/tasks flow, set `flow: full` in `.specclaw/config.yaml` afterwards.
