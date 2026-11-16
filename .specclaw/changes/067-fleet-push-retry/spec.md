# Spec: specclaw-fleet keeps a finished run when the push fails

**Change:** 067-fleet-push-retry
**Created:** 2026-11-16
**Status:** 🟡 Draft

## Overview

A fleet pod pushes the change branch once and treats a failure as a warning, so one rejected push loses the whole run. This change retries the push, reports a failed push as what it is, and keeps the unpushed commits on a PVC so the next run can resume from them.

## Approach

The pod's push stays in `image/tracker.sh`; it gains a retry loop and a non-zero return, and `deliver` in `image/draft-pr.sh` turns that into `exit=push-failed`. Unpushed work is saved as a `git bundle` on a claim mounted by `subPath`, one folder per change; `image/workspace.sh` reads it back. Bundles are off unless `fleet.bundle_claim` is set, so existing clusters are untouched.

File map: `image/tracker.sh`, `image/draft-pr.sh`, `image/workspace.sh`, `image/entrypoint.sh` (only if a new sourced file is needed), `lib/settings.sh`, `lib/podspec.sh`, `lib/manifest.sh`, `lib/doctor.sh`, `lib/doctor-checks.sh`, `k8s/bundles-pvc.yaml`, `README.md`, `skills/setup/SKILL.md`, `tests/lib/entry-env.sh`, `tests/cases/ac40_push_retry.sh`, `tests/cases/ac41_bundles.sh`, `tests/cases/ac42_bundles_real_git.sh`, `tests/cases/ac10_manifests.sh`, `tests/cases/ac16_doctor.sh` (all under `plugins/specclaw-fleet/`).

## Requirements

### Functional Requirements

- **FR-1** `push_change_branch` attempts the push up to `FLEET_PUSH_ATTEMPTS` times (default 4; must be 1–9) and pauses between attempts for the seconds listed in `FLEET_PUSH_PAUSES` (default `5 15 45`; the last value repeats; a value other than whole seconds separated by blanks warns and uses the default). Before the final attempt it runs `git repack -a -d -f`. It stops at the first success. Each attempt is cut off after `FLEET_PUSH_TIMEOUT` seconds (default 120; must be 1–9999, else it warns and uses the default) with `timeout`, and git aborts a transfer slower than 1000 B/s for 60 s (`http.lowSpeedLimit`/`http.lowSpeedTime`); a cut-off attempt is a failed one whose error line is `push timed out after <n>s`. The whole delivery has a budget that ends 300 s after the agent's deadline (`FLEET_AGENT_TIMEOUT`, counted from pod start; the Job's `activeDeadlineSeconds` is that deadline plus 600): no pause or attempt starts unless it can end in time (an attempt gets at least 5 s and at most what is left), the repack runs only while more than two attempt timeouts are left, and when the budget is spent the remaining attempts are skipped with a warning (`push skipped: delivery budget spent` when none ran) and the pod goes straight to the record and the bundle.
- **FR-2** `push_change_branch` returns 0 with the branch name on success, 0 with no output when there is nothing to push (HEAD is not the change branch), and non-zero when every attempt failed. It keeps git's last error line in `$STATUS/push-error`, redacted with the same patterns as `show_agent_log`.
- **FR-3** On a failed push `deliver` records `state=failed exit=push-failed push_error=<line> bundle=saved|none|off`, plus `cause=deadline` when it runs for the deadline rather than after an agent exit, and the pod finishes with exit code 4. It does not call the pull-request API.
- **FR-4** `fleet.push_attempts` and `fleet.bundle_claim` are fleet settings. `bundle_claim` is a security setting (read from the base branch in pipeline runs) and must be a valid Kubernetes object name.
- **FR-5** With `bundle_claim` set, the Job mounts that claim in the agent container only, at `/fleet/bundles`, with `subPath` `<host>/<url path>/<change>`: the full host (user part dropped, lower case) and every path segment of the repo URL except `_git` and a trailing `.git`. In each segment, bytes outside `[A-Za-z0-9.-]`, and `_` itself, become `_XX`, so two repositories never share a folder; a dot-only segment gets a `_` prefix. The pod sets `fsGroup` so the non-root agent can write there. With it unset the rendered Job is byte-identical to today's.
- **FR-6** With `bundle_claim` set, dispatch refuses to launch when `node_label` is unset, naming both settings.
- **FR-7** When every push attempt fails and `/fleet/bundles` is writable, the pod writes `work.base` (the base commit) and `work.bundle` (`git bundle create` of `<base>..HEAD` on the change branch) there, each to a temporary name renamed into place, base first, replacing any earlier pair, and adds `bundle=saved` to the record. When the folder does not exist (no `bundle_claim`) it adds `bundle=off`; when it is not writable, or the save fails, it adds `bundle=none`; either way it still exits 4; an older pair is then kept only if it still passes `git bundle verify`.
- **FR-7a** A saved bundle that holds a tip the change branch does not contain is never overwritten. Before saving, the pod moves that pair to the first free `kept-<n>.bundle` and `.base` in the same folder (without replacing an existing file) and the record carries `bundle=saved,kept=<name>` or `bundle=none,kept=<name>`. When the move fails, nothing is written and the record carries `bundle=none`. When the bundle moves but its `work.base` cannot, the pod warns, leaves `work.base` in place and the record adds `kept_base=none`.
- **FR-8** `prepare_workspace` checks out the remote change branch when one exists. Then, when `work.bundle` exists, passes `git bundle verify`, and `work.base` is a full commit id (40 or 64 lower-case hex) that is an ancestor of the cloned HEAD, it fetches the bundle's change branch. With no remote branch, or when the remote tip is an ancestor of the bundle tip, it moves the change branch to the bundle tip, printing `resuming from saved bundle`. When the bundle tip is already in the remote branch it does nothing; when the two diverged it keeps the remote branch, warns naming the bundle, and leaves the bundle in place. A bundle that fails a check is left in place and ignored with a warning; `work.base` is never printed.
- **FR-9** After a successful push the pod deletes `work.bundle` and `work.base` only when the pushed HEAD contains every tip in the bundle, or the file is not a readable bundle; otherwise it keeps them and warns.
- **FR-10** `specclaw-fleet doctor` gains a `bundles` line: `ok bundles: off` when `bundle_claim` is unset; `missing bundles: …` naming the fix when the claim is absent, or is neither Bound nor Pending without a selected node, or when `node_label` is unset (on any cluster size, the same rule as FR-6, shared with dispatch), or when `node_label` matches zero or several nodes, or when the claim's `volume.kubernetes.io/selected-node` names another node than the one `node_label` matches (`missing bundles: claim <c> lives on <A>, fleet.node_label matches <B>`); `skip bundles: …` when the cluster or the node list cannot be read; otherwise `ok bundles: <claim>`, or `ok bundles: <claim> (binds on first use)` for a claim that is Pending with no `volume.kubernetes.io/selected-node` annotation (a WaitForFirstConsumer class such as k3s local-path, before any Job mounts it).
- **FR-11** `k8s/bundles-pvc.yaml` defines the claim `fleet-bundles` (1Gi, `ReadWriteOnce`, no storage class named) in the `specclaw-fleet` namespace, like the other manifests in `k8s/`. The setup skill and README say when to apply it, that `node_label` is then required and must match one node, and that another `fleet.namespace` means editing the namespace name in the `k8s/` files, because `kubectl apply -n` is refused for a file naming another namespace.

- **FR-12** Dispatch stamps `FLEET_HARD_DEADLINE` into the Job: the wall-clock second at which the Job's `activeDeadlineSeconds` ends, taken at render time (so never later than the real one). The pod stops its agent at the agent deadline and never later than 480 s before `FLEET_HARD_DEADLINE` (a pod with less than that left never starts the agent), and stops pushing 300 s after the agent deadline and never later than 180 s before `FLEET_HARD_DEADLINE`, so the time spent on scheduling and the image pull is counted. `git bundle create` is cut off after 120 s. This env is in every Job, so AC-5's "unchanged when unset" covers the bundle parts only.

### Non-Functional Requirements

- **NFR-1** No credential appears in `push_error`, the work item, or the pod log.
- **NFR-2** Added time is bounded: at most the delivery budget of FR-1 (the agent's deadline plus 300 s), inside the pod's delivery path, which already ignores TERM. With defaults (4 attempts of at most 120 s, pauses 5, 15, 45 s) a run that ends before its deadline adds at most 545 s plus the repack.
- **NFR-3** The repo's existing file and test conventions hold (`tests/run-fleet-tests.sh` passes; shellcheck clean).

## Acceptance Criteria

1. **AC-1** A push that fails once and then succeeds ends `state=pr_open`, with two push attempts made and no `push_error` recorded.
2. **AC-2** A push that fails every time ends `state=failed exit=push-failed`, makes exactly `FLEET_PUSH_ATTEMPTS` attempts with a repack before the last, exits 4, and opens no pull request.
3. **AC-3** `push_error` holds git's last error line with tokens redacted; a line containing `sk-ant-…` or a 40-character secret is not recorded verbatim.
4. **AC-4** HEAD on the base branch is still not a failure: no push, no pull request, exit code unchanged.
5. **AC-5** With `bundle_claim` unset, `dispatch --dry-run` output equals the output before this change. With it set, the Job has the claim volume, the agent mount with the expected `subPath`, `fsGroup`, and no mount in `writeback`.
6. **AC-6** With `bundle_claim` set and `node_label` unset, dispatch exits non-zero and names both settings.
7. **AC-7** After a fully failed push with a writable bundle folder, `work.bundle` and `work.base` exist and the record carries `bundle=saved`; without `bundle_claim` it carries `bundle=off`; with the claim set and a missing or read-only folder it carries `bundle=none`. The Job passes `FLEET_BUNDLES=on` to the pod when the claim is set, and the pod decides `off` from that, never from the folder.
8. **AC-8** A new run with no remote branch and a valid bundle resumes from it; with a remote branch it fast-forwards to a newer bundle, ignores one already pushed, and keeps a diverged one with a warning; a corrupt bundle, a base that is not an ancestor, or a `work.base` that is not a full commit id is ignored with a warning.
9. **AC-9** A successful push removes the bundle pair when the pushed branch holds the bundle tip or the bundle is unreadable, and keeps it with a warning otherwise.
10. **AC-10** `doctor` prints the `bundles` line in each of its four states.
11. **AC-11** `kubectl apply --dry-run=client -f k8s/bundles-pvc.yaml` accepts the manifest, and the README and setup skill describe `bundle_claim`, `push_attempts` and the `node_label` requirement.
12. **AC-12** On a real cluster with the claim applied: a job whose push is forced to fail leaves a bundle, and `trigger --retry` resumes from it and opens a pull request. (Operator check; not runnable in the test suite.)

## Edge Cases

- Two jobs for the same change cannot run at once (existing claim lock), so the bundle folder has one writer.
- A bundle older than the base branch's history rewrite fails the ancestor check and is ignored.
- `FLEET_PUSH_ATTEMPTS=1` means no retry and no repack.
