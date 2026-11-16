# Proposal: specclaw-fleet keeps a finished run when the push fails

**Created:** 2026-11-16
**Status:** 🟡 Draft

## Problem

A fleet job that finishes its work can lose all of it to one failed `git push`.

On 2026-11-16 a job ran for 22 minutes, made 16 commits and passed its tests. The pod then pushed the change branch once. Azure DevOps rejected the push:

```
error: remote unpack failed: error The archive entry was compressed using an unsupported compression method.
 ! [remote rejected] HEAD -> specclaw/004-... (The archive entry was compressed using an unsupported compression method.)
WARNING: could not push specclaw/004-...
```

`push_change_branch` in `plugins/specclaw-fleet/image/tracker.sh` makes one attempt, prints a warning and returns success. `deliver` then records `state=failed exit=0` with an empty `branch`, the job completes, and the pod's `emptyDir` workspace is deleted with it. The commits are gone, and the plan allowance the run spent bought nothing.

The work item gives no reason. It reads `failed exit=0`, which looks like an agent failure. The push error is only in the pod log, which is gone once the job's TTL passes.

The rejection was not reproducible: 11 test pushes from the same image (`0.9.5`, on arm64 and amd64) to the same repository were all accepted, covering archives, random and zero-filled binaries, an empty file, a symlink, 400 new files and a 16-commit history with and without `git gc`. Community reports describe this Azure DevOps error as intermittent. A second attempt would very likely have saved the run.

## Proposed Solution

Make the pod's push persistent and its failure visible.

1. **Retry.** `push_change_branch` tries the push up to `FLEET_PUSH_ATTEMPTS` times (default 4) with a growing pause (5 s, 15 s, 45 s). Before the last attempt it runs `git repack -a -d -f`, so the pack sent is rebuilt from scratch.
2. **Say why.** When every attempt fails, `deliver` records `state=failed exit=push-failed` and a `push_error` field holding the last error line from git, with credentials redacted the same way `show_agent_log` does it.
3. **Fail the job.** The pod exits non-zero on `push-failed`, so `specclaw-fleet status` and the pipeline show a failed run, not a completed one.
4. **Keep the work on a PVC.** A new PersistentVolumeClaim `fleet-bundles` in the fleet namespace holds unpushed work. Each job mounts only its own folder, by `subPath` `<org>/<project>/<repo>/<change>`, so a pod can never read another change's or another repository's bundle. When every push attempt fails, the pod writes `git bundle create <mount>/work.bundle <base>..HEAD` there, with the base commit beside it. On `specclaw-fleet trigger <change> --retry`, `prepare_workspace` resumes from the remote branch when one exists, and otherwise from the bundle after `git bundle verify`. The pod deletes the bundle once a push succeeds. `specclaw-fleet doctor` checks that the claim is bound and reports bundles older than 14 days.

5. **Pin fleet jobs to one node.** The claim is `ReadWriteOnce`, so every job that mounts it must run on the same node. The existing `fleet.node_label` setting (`key=value`, for example `kubernetes.io/hostname=k3s-worker`) already puts a `nodeSelector` on every job; it becomes required when bundles are on. On a cluster with more than one node, `specclaw-fleet doctor` fails the `bundles` line when it is unset. Decided by the operator on 2026-11-16: pinning, not a `ReadWriteMany` storage class.

The agent's own push (when verify passes and the agent opens the pull request) is unchanged; if it fails, the pod's `deliver` still runs and now retries.

## Scope

### In Scope
- `plugins/specclaw-fleet/image/tracker.sh`: retry loop, repack before the last attempt, redacted last error.
- `plugins/specclaw-fleet/image/draft-pr.sh`: `exit=push-failed`, `push_error`, non-zero finish.
- `plugins/specclaw-fleet/image/workspace.sh`: resume from a saved bundle.
- `plugins/specclaw-fleet/k8s/`: the `fleet-bundles` PersistentVolumeClaim (1Gi, the cluster's default storage class).
- The job template in dispatch: mount the claim by `subPath` for the job's own change only.
- `specclaw-fleet doctor`: a `bundles` line (claim bound, stale bundles, node selector set on a multi-node cluster).
- `fleet.bundle_claim` in `config.yaml` turns bundles on; unset keeps today's behaviour, so an upgrade breaks no cluster.
- The setup skill: the new manifest is applied with the others.
- `FLEET_PUSH_ATTEMPTS` read from `fleet.push_attempts` in `config.yaml`, documented in the fleet README.
- Tests in `plugins/specclaw-fleet/tests/cases/`: push fails once then succeeds; push fails every time; the error text is redacted; resume from a bundle.
- A new fleet image tag.

### Out of Scope
- Finding why Azure DevOps rejected that one push.
- Pushing over SSH.
- Retrying the pull-request API call (`ensure_pr` already fails soft and a later run reuses the branch).
- Pushing work in progress during the agent's run.
- A `ReadWriteMany` storage class, or spreading fleet jobs over several nodes.

## Impact

- **Size:** bounded (spike / bounded / architectural)
- **Files affected:** 12 (estimated)
- **Complexity:** medium (small / medium / large)
- **Risk:** low (low / medium / high)

## Open Questions

- Should the bundle be kept after a successful retry for a short time, as a second copy, or deleted at once as proposed?
- Should a `push-failed` run count against the change's attempt limit?
- Is a 65-second worst-case wait acceptable inside the job deadline, or should the pauses be shorter?

---

**To proceed:** Review this proposal and approve to begin planning.
