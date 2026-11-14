# Spec: fleet pods work for any Azure DevOps project, and can run a Postgres sidecar

**Change:** 058-fleet-any-project-postgres
**Created:** 2026-11-11
**Status:** 🟡 Draft

## Overview

One fleet namespace must serve repos in several Azure DevOps projects, and a repo whose tests need
Postgres must be able to run on the fleet. The pod takes org and project from the repo it cloned, and
an optional Postgres sidecar starts before the agent.

## Requirements

### Functional Requirements

- **FR-1** For a `FLEET_REPO_URL` of the form `https://[user@]dev.azure.com/<org>/<project>/_git/<repo>`,
  the entrypoint exports `AZDO_ORG=<org>` and `AZDO_PROJECT=<project>` (percent-decoded), overriding
  the `fleet-azdo` secret. Any other URL leaves both untouched.
- **FR-2** New flat fleet settings `postgres_image`, `postgres_port`, `postgres_user`,
  `postgres_password`, `postgres_db` in `.specclaw/config.yaml` (flat, because the settings parser
  ignores nested keys). `postgres_image` is a secure key: it comes only from the trusted branch.
- **FR-3** With `postgres_image` set, `render_job` adds a native sidecar `initContainers` entry
  named `postgres`, before `agent`, with `restartPolicy: Always`, a `pg_isready` `startupProbe`,
  the restricted container securityContext, and `emptyDir` mounts for data, the socket dir and `/tmp`.
  The agent gets `PGHOST=127.0.0.1` and `PGPORT`.
- **FR-4** Defaults: port 5432, user/db `postgres`, password `postgres`.
- **FR-5** README, setup skill and doctor's `fleet-azdo` hint document the multi-project PAT, the
  postgres settings, and that a repo's Playwright version must match the image's.

### Non-Functional Requirements

- **NFR-1** Without `postgres_image`, the rendered Job is byte-identical to today's.
- **NFR-2** No change to the NetworkPolicy, egress proxy or RBAC.
- **NFR-3** Values are validated by pattern before rendering; nothing user-supplied is rendered unquoted.

## Acceptance Criteria

- **AC-1** Entrypoint table test: `dev.azure.com/o/p/_git/r` → `o`/`p`; `My%20Project` → `My Project`;
  `user@dev.azure.com/...` → same as without user; trailing `/` and `.git` handled; GitHub and
  `*.visualstudio.com` URLs and a URL without `_git` keep the secret's values. (FR-1)
- **AC-2** Settings table test: absent → no `FLEET_POSTGRES_*`; valid block exported; image without
  `@sha256:` refused; port outside 1–65535 refused; user/db/password with characters outside
  `[A-Za-z0-9_-]` refused; a branch that changes `postgres_image` versus the trusted branch refused. (FR-2, NFR-3)
- **AC-3** Manifest test: with postgres set, the Job has `postgres` before `agent` in `initContainers`
  with `restartPolicy: Always` and a `pg_isready` probe on the port, and the agent env has `PGPORT`;
  without it, the output equals the output rendered before this change (golden). (FR-3, FR-4, NFR-1)
- **AC-4** `grep` shows the README and setup skill mention `postgres_image`, the multi-project PAT and
  the Playwright version rule. (FR-5)

## Edge Cases

- Project names with spaces arrive as `%20`; decode only `%XX` sequences, never evaluate them.
- A preset `AZDO_REPO` still wins (056); org/project from the URL always win for dev.azure.com.
- `postgres_password` is a throwaway test value; `looks_secret` still rejects anything token-shaped.

## Approach

Decision: flat `postgres_*` keys reuse the existing `fleet:` parser and trusted-branch check; rendering
lives next to the other optional pod parts in `podspec.sh` and is spliced into `render_job` as
`$(render_sidecars)` / `$(render_sidecar_env)` / `$(render_sidecar_volumes)`, each printing nothing when
unset, so NFR-1 holds by construction. File map:
- `plugins/specclaw-fleet/image/entrypoint.sh` — FR-1
- `plugins/specclaw-fleet/lib/settings.sh` — FR-2 keys, secure key, validation
- `plugins/specclaw-fleet/lib/podspec.sh`, `lib/manifest.sh` — FR-3, FR-4
- `plugins/specclaw-fleet/lib/doctor.sh`, `README.md`, `skills/setup/SKILL.md` — FR-5
- tests: `tests/cases/ac7_entrypoint.sh`, `tests/lib/entry-env.sh`, `ac22_settings.sh`, new `ac32_postgres_sidecar.sh`
- version bump: every `plugin.json` and both `marketplace.json` (R1)
