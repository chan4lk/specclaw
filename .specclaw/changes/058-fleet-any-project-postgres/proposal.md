# Proposal: fleet pods work for any Azure DevOps project, and can run a Postgres sidecar

**Created:** 2026-11-11
**Status:** 🟡 Draft

## Problem

Onboarding a second repo, BistecGlobal/AI-Adoption-Index, onto the `bistec-dev-uat` fleet that already serves demo-studio surfaced two blockers.

- **One namespace, one project.** Every Job gets `AZDO_ORG`, `AZDO_PROJECT` and `AZDO_TOKEN` through `envFrom: fleet-azdo`. That secret pins `AZDO_PROJECT=Product-Portal`. A pod working on AI-Adoption-Index would build the change and then call `…/Product-Portal/_apis/git/repositories/AI-Adoption-Index/pullrequests` (`image/draft-pr.sh:32`, and `specclaw-azdo-pr` through the same env). The repo is not in that project, so the PR fails. Today the only workaround is a second namespace, with its own RBAC, NetworkPolicy, secrets and an edit to the shared egress proxy's ingress policy, for every project.
- **No database in the pod.** AI-Adoption-Index's `build.test_command` imports a fresh-database helper that needs Postgres at `127.0.0.1:55432`. The Job has an agent and a write-back container only, so every DB-backed test fails and build marks the tasks `failed`. Any repo whose tests need a database cannot use the fleet.

## Proposed Solution

1. **Project from the clone URL.** `image/entrypoint.sh` already derives `AZDO_REPO` from `FLEET_REPO_URL` (056). For an Azure DevOps URL, `https://dev.azure.com/<org>/<project>/_git/<repo>`, it also exports `AZDO_ORG` and `AZDO_PROJECT` (URL-decoded), overriding the secret's values: the repo the pod cloned is the authority. Other URLs (GitHub, `*.visualstudio.com`) keep the secret's values. The `fleet-azdo` PAT must then reach every project it serves; doctor and setup say so.
2. **Optional Postgres sidecar.** A new `fleet.services.postgres` block in the trusted `.specclaw/config.yaml` (read from the trusted branch, like every fleet setting): `image` (must be pinned by digest), `port`, `user`, `password`, `db`. When present, the Job gets a native sidecar (`initContainers` entry with `restartPolicy: Always`, ahead of `agent`) that:
   - runs under the pod's restricted security context (uid 1000, read-only root, writable `emptyDir` for data, socket and `/tmp`);
   - is ready only when `pg_isready` passes (`startupProbe`), so the agent starts after the database;
   - stops with the Job, because native sidecars end when the main container exits.
   It talks over `localhost` inside the pod, so the NetworkPolicy and egress proxy are untouched. The values are a throwaway test database, never a credential; they are validated by pattern and rendered with `yaml_str`.
3. **Docs.** README and the setup skill: `fleet.services.postgres`, the multi-project PAT, and that a repo's Playwright version must match the image's (`PLAYWRIGHT_VERSION`, 1.65.0) because the image's browsers are read-only and the CDN is not on the allowlist.

## Scope

### In Scope
- `plugins/specclaw-fleet/image/entrypoint.sh` (org and project from the URL), with a table test in `tests/cases/ac7_entrypoint.sh` (dev.azure.com with spaces and `%20`, `_git` missing, GitHub, visualstudio.com, trailing `.git` and `/`).
- `plugins/specclaw-fleet/lib/settings.sh` (read and validate `fleet.services.postgres`), `lib/podspec.sh` and `lib/manifest.sh` (render the sidecar and its volumes), with table tests in `tests/cases/ac10_manifests.sh` / `ac22_settings.sh` (absent, valid, unpinned image, bad port, bad name characters).
- `plugins/specclaw-fleet/README.md`, `skills/setup/SKILL.md`, doctor's `fleet-azdo` line hint.
- Version bump across all plugins (rule R1).

### Out of Scope
- Other services (Redis, MSSQL). The block is shaped so they can follow, but only Postgres ships.
- Putting the Playwright CDN on the egress allowlist, or a writable browser path. Repos align with the image's Playwright version instead.
- Per-project `fleet-azdo` secrets, or a PAT per project.
- AI-Adoption-Index's own changes (its `fleet.services.postgres` block, the Playwright bump); those land in that repo.

## Impact

- **Size:** bounded (alters the existing Job manifest and pod entrypoint; no new subsystem)
- **Files affected:** ~9 (estimated)
- **Complexity:** medium
- **Risk:** medium. The manifest change touches every Job, but with no `services` block the rendered manifest is byte-identical to today's (asserted by test). The URL override changes behaviour only for dev.azure.com clones, where the secret's project was either the same or wrong.

## Open Questions

- Should the project from the URL also win when the secret's `AZDO_PROJECT` differs and the PAT cannot reach the URL's project? (Proposed: yes, and the PR step fails with a clear message; doctor warns at setup.)
- Default `port` when omitted: 5432 (Postgres default) or required? (Proposed: 5432.)
