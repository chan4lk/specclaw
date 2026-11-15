# Spec: specclaw-fleet setup and run skills

**Change:** 052-fleet-setup-and-run-skills
**Created:** 2026-11-07
**Size:** architectural

## Functional Requirements

- **FR-1 Public image without the Claude binary.**
  - The runner Dockerfile no longer downloads `claude`.
  - It installs `gnupg` and bakes in Anthropic's release public key at `/opt/fleet/claude-release.asc`. The build fails unless the key's fingerprint is `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`.
  - It sets `DISABLE_UPDATES=1`.
- **FR-2 Fetch and verify at pod start.** For `FLEET_AGENT=claude`, the entrypoint (after the egress gate):
  - downloads `manifest.json` and `manifest.json.sig` for `FLEET_CLAUDE_VERSION`;
  - verifies the signature with the baked key, requiring a `VALIDSIG` whose fingerprint equals the pinned one;
  - picks the platform from `uname -m` (`linux-x64` / `linux-arm64`);
  - downloads the binary into `$HOME/.fleet/bin/claude`, checks its SHA256 and size against the manifest, and makes it executable;
  - records `claude_fetch_s=<seconds>`.

  Any failure records `state=failed exit=claude-verify-failed`, and the agent never runs.
- **FR-3 Wrapper.** `/opt/fleet/bin/claude` execs `$HOME/.fleet/bin/claude` by default (`FLEET_REAL_CLAUDE` still overrides).
- **FR-4 Dispatch inputs.**
  - `FLEET_CLAUDE_VERSION` is required when the agent is claude, and is passed to the Job.
  - `FLEET_IMAGE_PULL_SECRET` (optional) adds `imagePullSecrets`.
  - `FLEET_NODE_LABEL=key=value` (optional) adds a `nodeSelector` and a `NoSchedule` toleration for that key and value.
  - All three are validated against strict patterns. Empty means absent.
- **FR-5 Prompt.** The review fix-round budget is "in this run".
- **FR-6 Image workflow.** `.github/workflows/fleet-image.yml` builds `linux/amd64` and `linux/arm64` with buildx and pushes `ghcr.io/<owner>/specclaw-fleet:<tag>`. It runs on tags `fleet-v*` or manual dispatch, with `permissions: packages: write`.
- **FR-7 `specclaw-fleet doctor`.**
  - Read-only. Prints one line per check as `ok|missing|wrong <name>: <detail>`, then `fix:` lines.
  - Exits 0 only when every check is `ok`.
  - Checks:
    - `context`: the kube context named by `FLEET_KUBE_CONTEXT` resolves;
    - `namespaces`;
    - `rbac`;
    - `egress`: the proxy deployment is ready;
    - `netpol`;
    - `secret:fleet-azdo` and `secret:fleet-vault-writer`: key names only;
    - `vault`: `FLEET_VAULT` is reachable;
    - `image`: the registry manifest for `FLEET_IMAGE` exists;
    - `pipeline`: the AzDO pipeline exists;
    - `service-connections`: ready.
- **FR-8 `specclaw-fleet trigger <change> [--retry] [--direct] [--create]`.** Gates, in order:
  1. The proposal is approved. Otherwise exit 1, and never approve on the user's behalf.
  2. A work item exists; `--create` creates it.
  3. It has an assignee.
  4. `fleet:auto` was added by the assignee. Otherwise exit 4, naming who must add it.
  5. The assignee's credential is registered.

  Then:
  - `--retry` removes `fleet:dispatched` and `fleet:refused`;
  - it queues the pipeline (`FLEET_PIPELINE`, default `specclaw-fleet`) or, with `--direct`, calls `dispatch`;
  - it prints JSON `{ok, mode, run|job, work_item}`.
- **FR-9 Hosted pipeline template.**
  - `pipelines/dispatch-hosted.yml`: `pool: vmImage: ubuntu-latest`.
  - A step clones specclaw at `$(fleetSpecclawRef)` and prepends `plugins/specclaw-fleet/bin` and `plugins/specclaw-sync/bin` to `PATH` via `##vso[task.prependpath]`.
  - It then runs the same Kubernetes login and dispatch script as `dispatch.yml`, with `FLEET_CLAUDE_VERSION`.
- **FR-10 Skills and docs.**
  - `skills/setup/SKILL.md` drives `doctor` until it is clean, handing every credential step to a real terminal and asking before every outward-facing action.
  - `skills/run/SKILL.md` drives `trigger`, then watches the Job and the work item until a PR (or draft PR) or a recorded failure.
  - The README setup section points to `/specclaw-fleet:setup`.

## Non-Functional Requirements

- NFR-1: every new or changed file is 80 lines or fewer, with no comments except tool pragmas; ShellCheck is clean at warning level.
- NFR-2: tests are offline and stub `kubectl`, `az` and `curl`. Signature tests use a throwaway GPG key generated in the test, never the real key.
- NFR-3: `doctor` never mutates anything. A test asserts that it makes no create, apply, patch, delete or POST calls.

## Acceptance Criteria

- **AC-1:** the Dockerfile contains no `claude-code-releases` download. It has `DISABLE_UPDATES=1`, the baked key, and a build-time fingerprint check.
- **AC-2:** with a valid signature and checksum, the pod installs `$HOME/.fleet/bin/claude`, records `claude_fetch_s`, and runs the agent.
- **AC-3:** each of these records `claude-verify-failed` and never runs the agent: a bad signature, a signature from a different key, a wrong checksum, and a missing platform.
- **AC-4:** the rendered Job carries `FLEET_CLAUDE_VERSION`, and carries `imagePullSecrets`, `nodeSelector` and the toleration only when their variables are set. Invalid values are refused.
- **AC-5:** the prompt says the budget applies in this run.
- **AC-6:** the workflow builds both platforms, pushes to GHCR, and grants `packages: write` only.
- **AC-7:** `doctor` reports each check `ok` or not, exits non-zero when any check is not `ok`, and makes no mutating call.
- **AC-8:** each `trigger` gate stops with its documented exit code and message. `--retry` untags both tags, `--direct` dispatches, and the default path queues the pipeline.
- **AC-9:** the hosted template uses `ubuntu-latest`, clones specclaw at a pinned ref, and prepends both bin directories to PATH.
- **AC-10:** both skills exist, and every suite is registered in CI.

## Edge Cases

- `uname -m` reports `aarch64` on arm64 Linux; it maps to `linux-arm64`.
- A manifest whose checksum is valid but whose size differs is refused.
- If `FLEET_CLAUDE_VERSION` is unset, dispatch refuses claude jobs before anything is created.
