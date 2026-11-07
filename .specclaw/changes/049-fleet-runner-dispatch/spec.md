# Spec: specclaw-fleet — sandboxed K3s jobs running Claude or Codex on the assignee's own plan

**Change:** 049-fleet-runner-dispatch
**Created:** 2026-11-07
**Size:** architectural

## Summary

A new add-on plugin, `plugins/specclaw-fleet/`. An approved specclaw change is run headless in a K8s Job on K3s, with either `claude -p` or `codex exec`. The run uses the subscription credential of the person the change's Azure Boards work item is assigned to. The work item records each run.

## Assumptions

- **A1:** The AzDO org is backed by Entra ID, so a work item's `System.AssignedTo.uniqueName` equals the user's Entra UPN, which is what `az account show --query user.name` prints for them.
- **A2:** Dispatch runs where `az` (logged in, with read access to the vault) and `kubectl` (namespace-scoped ServiceAccount) are available, typically an AzDO pipeline job.
- **A3:** Credential secret names are derived as `<agent>-<kind>-<h>`. `<h>` is the first 16 hex characters of `sha256(lowercase(UPN))`. This needs no Graph lookup, avoids collisions between UPNs, and keeps names within the Key Vault charset.
- **A4:** The change already has an Azure Boards work item (`specclaw-azdo-issue create`), so `status.md` carries `**Azure Boards Work Item:** [#<id>]`.

## Functional Requirements

- **FR-1 Plugin packaging.** `plugins/specclaw-fleet/` ships:
  - a Claude manifest and a Codex manifest at the shared version;
  - an entry in both `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`;
  - `skills/` exposed to both hosts.

  Core `plugins/specclaw/` code is not changed. The only exception is that the Codex packaging test's plugin inventory gains the new name.
- **FR-2 Onboard (admin).** `specclaw-fleet onboard <upn> --vault <name>`:
  - creates placeholder secrets `claude-token-<h>` and `codex-auth-<h>` when they are missing;
  - assigns `Key Vault Secrets Officer` to that user at each secret's own scope, never at vault scope;
  - with `--writer <object-id>` (or `FLEET_VAULT_WRITER`), also grants the write-back service principal `Key Vault Secrets Officer` on that user's `codex-auth-<h>` only;
  - is idempotent, and writes the placeholder only when the secret is `SecretNotFound`.
- **FR-3 Login (user).** `specclaw-fleet login --agent claude|codex --vault <name>`:
  - derives `<h>` from the caller's own `az` identity;
  - **claude:** runs `claude setup-token` and stores the printed token as a new version of `claude-token-<h>`;
  - **codex:** runs `codex login` with file credential storage in a temporary `CODEX_HOME`, then stores that `auth.json` as `codex-auth-<h>`;
  - never writes a token to stdout, the logs, or any file outside a temporary directory, which is removed on every exit path.
- **FR-4 Dispatch gates.** `specclaw-fleet dispatch <change> [--agent claude|codex] [--ref <branch>] --vault <name>` refuses with a non-zero exit, and creates nothing, when any of these hold:
  - (a) the change's proposal phase is not approved;
  - (b) the change has no work item;
  - (c) the work item has no assignee;
  - (d) **consent is missing:** no `fleet:auto` tag (case-insensitive) added by the assignee according to the work-item history, and the requester is not the assignee;
  - (e) the assignee has no usable credential for the chosen agent, meaning the secret is missing, empty, or still a placeholder. A vault read error is refused separately, as a vault problem;
  - (f) `--agent codex` is chosen while that assignee already has an unfinished codex Job. The codex Job name `fleet-codex-<h>` is the atomic claim: the API refuses a duplicate, and a finished one is replaced by a delete carrying a UID precondition.

  - (g) the work item is already tagged `fleet:dispatched` or `fleet:refused` (case-insensitive). Exits 3, unless `--force` is given.

  Refusals (c)–(f) exit 4, set the work item to `Failed`, comment the reason and tag `fleet:refused`. Dispatch never uses a credential belonging to anyone other than the assignee.
- **FR-5 Dispatch launch.** When every gate passes, dispatch:
  - creates the Job, then a K8s Secret holding only the assignee's credential with `ownerReferences` to that Job already set, so it is garbage-collected with the Job and the dispatcher never needs read or patch access to Secrets;
  - labels the Job `specclaw.fleet/agent`, `specclaw.fleet/assignee=<h>` and `specclaw.fleet/change`;
  - sets `backoffLimit: 0`, `ttlSecondsAfterFinished`, and `activeDeadlineSeconds` = agent deadline + 600 s, so the in-pod watchdog (`FLEET_AGENT_TIMEOUT`) fires first and write-back still runs;
  - writes the work item fields (agent, job, cluster, branch, attempt, requested-by) and the state `Dispatched`;
  - prints one JSON line: `{"ok":true,"job":…,"agent":…,"work_item":…}`.

  Settings come from flags or environment variables (`FLEET_VAULT`, `FLEET_DEFAULT_AGENT` default `claude`, `FLEET_REF` default `main`, `FLEET_IMAGE`, `FLEET_NAMESPACE`, `FLEET_DEADLINE_MINUTES` 1–1440 default 120), never from `config.yaml`. On success the work item is tagged `fleet:dispatched`.
- **FR-6 In-pod agent run.** The Job's agent step:
  1. unsets `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `OPENAI_API_KEY` and `CODEX_API_KEY`;
  2. clones the repo at the ref over HTTPS, using an `Authorization` header, never a token in the URL;
  3. sets the work item to `Running`;
  4. runs the agent headless with permissions bypassed:
     - claude: `claude -p … --dangerously-skip-permissions`, with `CLAUDE_CODE_OAUTH_TOKEN` from the secret;
     - codex: `codex exec --dangerously-bypass-approvals-and-sandbox …`, with `CODEX_HOME` on a writable emptyDir seeded from the secret;
  5. sets `PR Open` when the change's `state.json` records a PR URL, otherwise `Failed`, and records the exit status.

  The agent step always exits 0 and writes its real status to a shared file, so the follow-on step runs even after a failed run.
- **FR-7 Codex write-back.** After a codex run, a separate container writes the refreshed `auth.json` back to `codex-auth-<h>`. It does so only when its sha256 differs from the original, the file is a regular file (not a symlink), and it holds `tokens.refresh_token`. The container has its own HOME, mounts the codex directory read-only and calls `curl -q`.
  - It holds the vault credential. That credential is mounted into this container only.
  - It never runs for claude.
  - It exits with the agent's recorded status, so the Job's success or failure is truthful.
- **FR-8 Work-item fields.** `specclaw-azdo-issue fields <dir> <change> key=value…` (specclaw-sync):
  - maps each key through `azdo.fleet_fields.<key>` in config, and `state` through `azdo.fleet_states.<value>`;
  - skips an unmapped key with a warning, and never sends a field the process may not have;
  - always adds one comment that lists every pair, so the record exists even with no custom fields;
  - exits 0 when nothing maps.
- **FR-9 Sandbox manifests.** `k8s/` ships:
  - the `specclaw-fleet` namespace with Pod Security `restricted` enforced (Jobs set `seccompProfile: RuntimeDefault`), and a separate `specclaw-fleet-egress` namespace (`baseline`) for the proxy;
  - a dispatch ServiceAccount whose Role allows only create/get/list/delete on `jobs` and create on `secrets` in that namespace, so it can never read the namespace's other Secrets;
  - a default-deny `NetworkPolicy` that lets fleet pods reach only DNS and the egress proxy;
  - a Squid proxy with an allowlist ConfigMap;
  - blocking of `169.254.169.254`.

  Pods run non-root, with a read-only root filesystem, emptyDir workspace and home, and `automountServiceAccountToken: false`.
- **FR-10 Pipeline template.** `pipelines/dispatch.yml` triggers on `main` for paths `.specclaw/changes/*/state.json`, with `batch: true` so runs never overlap. It scans every change with `phase: proposal` and an approved proposal, and calls dispatch for each. Dispatch is idempotent: a change tagged `fleet:dispatched` or `fleet:refused` exits 3 and is skipped. A refusal exits 4 and only warns. An unreadable `state.json` or any other error fails the step. It never polls and never diffs commits.

## Non-Functional Requirements

- **NFR-1:** Bash + coreutils, plus `jq`/`python3` where `bin/` already allows them. Every new script is ShellCheck-clean against the existing gate.
- **NFR-2:** Tests are offline. They stub `az`, `kubectl`, `curl`, `claude`, `codex`, `git` and the AzDO REST calls, and every suite is registered in `ci.yml`.
- **NFR-3:** No secret value appears in any rendered manifest, log line, JSON output, or test transcript. Tests assert this with a canary value.
- **NFR-4:** Change names are opaque. Job names and label values are derived safely (lowercase `[a-z0-9-]`, ≤ 63 characters), and no change name is interpolated into a regex.
- **NFR-5:** Every dispatch is headless-safe. No prompt runs without a TTY, and `login` is the only interactive command.

## Acceptance Criteria

- **AC-1:** Both marketplaces list `specclaw-fleet`. Its two manifests match every other plugin's version. `run-codex-plugin-tests.sh` passes with the new name in its inventory.
- **AC-2:** `onboard` issues role assignments whose scopes end in `/secrets/claude-token-<h>` and `/secrets/codex-auth-<h>`, and none at vault scope. A second run makes no duplicate assignments.
- **AC-3:** `login` stores the stub token under the caller's `<h>`. The canary token never appears on stdout or stderr, and the temporary directory is gone afterwards.
- **AC-4:** Each refusal case FR-4 (a)–(f) exits non-zero and creates no K8s object. For (c)–(f), it also sets the work item to `Failed` with a comment.
- **AC-5:** With every gate passing, dispatch creates exactly one Job and one Secret. The Secret holds only the assignee's credential and is owned by the Job. The Job carries the three labels and the deadline. The work item gets `Dispatched` and the run fields. The output is the JSON line.
- **AC-6:** A second codex dispatch for the same assignee is refused while the first Job is active, and allowed once it has finished. Of two concurrent codex dispatches, exactly one wins. Claude dispatches for the same assignee are never refused for concurrency.
- **AC-7:** The in-pod entrypoint unsets all four API-key variables before invoking the agent, and the clone URL contains no token. It sets `Running`, then `PR Open` or `Failed`. It exits 0 even when the agent fails, with the real status in the status file.
- **AC-8:** Write-back puts `codex-auth-<h>` only when the hash changed. It skips claude runs and exits with the agent's recorded status.
- **AC-9:** `specclaw-azdo-issue fields` sends PATCH ops only for mapped keys, and adds one comment that lists every pair. With nothing mapped, it sends no PATCH and exits 0.
- **AC-10:** The rendered Job YAML has `automountServiceAccountToken: false`, `runAsNonRoot: true`, `readOnlyRootFilesystem: true` and `backoffLimit: 0`. `k8s/` holds the NetworkPolicy, the proxy and the RBAC objects, and the Role's verbs and resources are exactly those in FR-9.
- **AC-11:** Every new suite is registered in `.github/workflows/ci.yml`, and the ShellCheck gate passes with the baseline unchanged.

## Edge Cases

- A change name holding shell or regex metacharacters still yields a valid Job name and label.
- The secret version holds the onboarding placeholder `__unset__`. That is treated as missing (FR-4e).
- AssignedTo uses different case from the `az` UPN. Hashing lowercases first, so the names still match.
- An unfinished codex Job is one that has neither `succeeded` nor `failed` status. A Job whose pod is Pending still counts as unfinished.
- Creating the Secret fails after the Job was created. Dispatch deletes the Job before exiting non-zero.
- `activeDeadlineSeconds` kills the agent. The SIGTERM trap writes `Failed` with exit reason `deadline`.

## Out of Scope

As in `proposal.md`, plus:
- A reaper for pods killed without SIGTERM. This is a follow-up.
- Workload identity for the AzDO clone token. v1 uses a scoped PAT in a K8s Secret, documented in the README.
