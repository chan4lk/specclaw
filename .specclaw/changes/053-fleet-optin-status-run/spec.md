# Spec: specclaw-fleet opt-in, status, many-change run, fleet: config

**Change:** 053-fleet-optin-status-run
**Created:** 2026-11-08
**Size:** bounded

## Functional Requirements

- **FR-1 `fleet:` config block.** At startup, `specclaw-fleet` reads `fleet:` from `$SPECCLAW_DIR/config.yaml`. For each known key, it exports the mapped env variable **only when that variable is unset**. An empty but set variable still wins over config. Flags are parsed afterwards, so the precedence is: flag, then env, then config, then built-in default.
  - **Keys:** `vault`, `kube_context`, `kubeconfig`, `cluster_name`, `namespace`, `image`, `claude_version`, `default_agent`, `deadline_minutes`, `pipeline`, `kube_connection`, `azure_connection`, `remote`, `ref`, `image_pull_secret`, `node_label`.
  - **Mapping:** each key goes to `FLEET_<KEY>`, except `kubeconfig`, which goes to `KUBECONFIG`.
  - **Values:** quotes, inline `#` comments and CRLF are handled. An unknown key gets a warning and is ignored.
  - **Secrets refused:** a value that looks like a secret (an `sk-` prefix, a JWT `eyJ…`, or a run of 52 or more base64 characters that is not an `@sha256:` digest) makes the command die, naming the key and never the value.
- **FR-2 Pipelines use config.**
  - Both templates drop the `fleetVault`, `fleetImage`, `fleetNamespace`, `fleetDeadlineMinutes`, `fleetDefaultAgent` and `fleetClaudeVersion` variables and their env entries.
  - They keep the two connection names and `fleetSpecclawRef`.
  - The dispatch script sets `export FLEET_KUBE_CONTEXT=` (set but empty), so the pipeline uses the kubeconfig that the Kubernetes task logged in.
- **FR-3 `specclaw-fleet optin <change>... [--dry-run]`.**
  - The caller is the `AZDO_TOKEN` identity, read from `specclaw-azdo-issue whoami` (AzDO `connectionData`).
  - For each change, one rev-guarded PATCH (`specclaw-azdo-issue optin`) sets `System.AssignedTo` to the caller when the item is unassigned, and adds `fleet:auto`.
  - An item assigned to someone else is refused (exit 4), naming the assignee, and gets no write.
  - An item already assigned to the caller and already tagged is a no-op.
  - A missing work item: exit 1, "run trigger --create".
  - **Exit status:** 0 if every change succeeds; otherwise the highest per-change code.
- **FR-4 `specclaw-fleet status [<change>...] [--json] [--watch [N]] [--since ISO]`.** Read-only.
  - **Header line:** the latest run of `fleet.pipeline` (id, status, result).
  - **One row per change, with these columns:**
    - the change;
    - the work item `#id`;
    - its state;
    - the assignee;
    - which fleet tags it has (`auto`, `dispatched`, `refused`);
    - the last fleet record newer than `--since`: `state`, `exit`, `pr`, `draft`, or `waiting` if there is none;
    - the newest Job labelled with the change, with its phase (`active`, `complete` or `failed`) and pod phase.
  - **Changes listed:** with no arguments, every change whose proposal is approved.
  - **`--watch`:** re-renders every N seconds (default 20). It exits when every row's record is `pr_open` or `failed`, or when the change is not opted in. In watch mode, `--since` defaults to the moment the watch started.
  - **Failures:** an unreadable cluster or AzDO prints `?` in that column, never a guess.
- **FR-5 `specclaw-azdo-issue` additions.** Each prints JSON:
  - `whoami`: the AzDO identity behind `AZDO_TOKEN`;
  - `optin <dir> <change> <upn>`: as in FR-3, same rev-retry and HTTP-outcome rules as `tag_update`;
  - `records <dir> <change>`: the fleet run-update comments, newest first, each parsed to key/value pairs with the comment's `createdDate`.
- **FR-6 `/specclaw-fleet:run` handles one or many changes.**
  1. Show status.
  2. Opt-in: one confirmation that names the caller and lists the items. Never assign to anyone else.
  3. Warn about plan spend and overlapping changes, then trigger every change in parallel (`--sequential` triggers one at a time, each after the previous finishes).
  4. Run `status --watch --since <trigger time>` until every change finishes.
  5. Report each change's PR, draft flag or `exit=` reason.
- **FR-7 Setup writes config.** `/specclaw-fleet:setup` records each confirmed value in the `fleet:` block as it goes. After setup, `doctor`, `trigger` and `status` run with no env prefix.
- **FR-8 Hosted-run fixes.**
  - **doctor and AzDO:** `doctor` checks the pipeline and the service connections over REST with `AZDO_TOKEN` (GET `_apis/pipelines`, `_apis/serviceendpoint/endpoints?endpointNames=…`, read `isReady`), not `az devops`. With no token, those checks are skipped.
  - **GHCR wording:** a GHCR token request answered 401 or 403 is reported as `missing image: package missing or private`.
  - **Run record:** `cluster=` is `FLEET_CLUSTER_NAME`, then `FLEET_KUBE_CONTEXT`, then the current context.
  - **Agent prompt:** it states that the pod pushes the change branch and opens the PR after the agent exits.
  - **trigger:** a change with no directory on the pushed ref fails with `no change <c> on <remote>/<ref>`.

## Non-Functional Requirements

- NFR-1: every new or changed fleet file is 80 lines or fewer, with no comments except tool pragmas. ShellCheck is clean at warning level.
- NFR-2: tests are offline and stub `curl`, `az` and `kubectl`. There is one table-driven test per AC, and each test fails without its fix.
- NFR-3: `status` and `doctor` never write. A test asserts that neither makes a PATCH, POST, create, apply or delete call.

## Acceptance Criteria

- **AC-1 Config precedence:** a config value fills an unset env variable. Env, including set-but-empty, and flags both beat config. Quotes, comments and CRLF parse correctly. An unknown key warns, and a secret-looking value dies without printing the value. Covers FR-1.
- **AC-2 Pipelines use config:** the templates carry no per-setting variables. The dispatch step clears `FLEET_KUBE_CONTEXT` and dispatches with config-derived settings. Covers FR-2.
- **AC-3 optin:** an unassigned item is assigned and tagged in one rev-guarded PATCH by the caller. An item assigned to someone else exits 4 with no write. An item already opted in is a no-op. `--dry-run` writes nothing. A race (409/412) retries. Covers FR-3 and FR-5.
- **AC-4 status:** the header and rows render the expected fields. Records older than `--since` show `waiting`. An unreadable AzDO or cluster shows `?`. `--watch` exits once every row is terminal. No write calls are made. Covers FR-4 and FR-5.
- **AC-5 Skills:** the run skill drives optin, a parallel trigger, `--sequential` and the watch. The setup skill writes `fleet:`. Every suite is registered in CI. Covers FR-6 and FR-7.
- **AC-6 Hosted-run fixes:** doctor's AzDO checks use the PAT REST call, 401/403 wording is right, `cluster=` resolves in the stated order, the prompt states delivery, and trigger names a missing change. Covers FR-8.

## Edge Cases

- `optin` for a change whose work item was deleted in Boards: the REST call returns 404, the command exits 1, and its message names the item.
- The PAT's identity is not the onboarded UPN. `optin` still works, but dispatch then refuses with "no registered credential". `run` warns about this up front by comparing `whoami` against the vault secret for that hash.
- A change named in `status` that has no work item: its row shows `no work item`.

## Approach

All configuration flows through one loader, `lib/settings.sh`. It exports env variables from `fleet:` before anything else runs, so every existing env read gains config support without per-call changes. Writes stay inside `specclaw-azdo-issue`, behind its rev-guarded PATCH core.

File map:
- **fleet lib (`plugins/specclaw-fleet/lib/`):** `settings.sh` (new), `optin.sh` (new), `status.sh` and `status-render.sh` (new), `doctor-azure.sh`, `launch.sh`, `trigger.sh`.
- **fleet bin and image:** `plugins/specclaw-fleet/bin/specclaw-fleet`, `image/entrypoint.sh`.
- **pipelines:** `plugins/specclaw-fleet/pipelines/dispatch.yml`, `dispatch-hosted.yml`.
- **skills and docs:** `plugins/specclaw-fleet/skills/{run,setup,dispatch}/SKILL.md`, `README.md`.
- **specclaw-sync:** `plugins/specclaw-sync/bin/specclaw-azdo-issue`, `plugins/specclaw-sync/tests/run-azdo-issue-optin-tests.sh` (new).
- **fleet tests:** `plugins/specclaw-fleet/tests/cases/ac22_settings.sh`, `ac23_optin.sh`, `ac24_status.sh`, `ac25_hosted_fixes.sh` (new); plus the existing pipeline tests.
- **CI and release:** `.github/workflows/ci.yml`, and the 0.9.0 bump of all manifests.
