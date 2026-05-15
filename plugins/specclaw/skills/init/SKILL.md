---
description: Initialize specclaw in this project. Creates the .specclaw/ directory, generates config.yaml from the template, and sets up the project dashboard. Run once per project before any other specclaw command.
disable-model-invocation: true
---

# specclaw init

Initialize SpecClaw in the current project.

1. Run `specclaw-init . [project_name] [project_description]`. This creates `.specclaw/` with `config.yaml` (from template), `STATUS.md`, and `changes/archive/`.
2. Ask the user for project name and description if not supplied.
3. Suggest adding `.specclaw/` to git tracking.

If `.specclaw/` already exists, the script exits with an error — do not overwrite.
