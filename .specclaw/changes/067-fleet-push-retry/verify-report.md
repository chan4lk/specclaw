# Verification Report: 067-fleet-push-retry

**Verified:** 2026-11-16
**Model:** Claude Fable 5.2 (criteria first judged by Sonnet 5.5 at commit 7b24de0; re-checked here at a27e780 after the review fixes)
**Verdict:** PARTIAL

## Acceptance Criteria

- ✅ **AC-1:** A push that fails once and then succeeds ends `state=pr_open` with two attempts and no `push_error` — `ac40_push_retry.sh` AC1.
- ✅ **AC-2:** A push that always fails ends `state=failed exit=push-failed`, makes exactly `FLEET_PUSH_ATTEMPTS` attempts with a repack before the last, exit 4, no pull request call — `ac40_push_retry.sh` AC2.
- ✅ **AC-3:** `push_error` holds git's last error line with tokens redacted; it is never empty — `ac40_push_retry.sh` AC3.
- ✅ **AC-4:** HEAD on the base branch is not a failure — `ac40_push_retry.sh` AC4.
- ✅ **AC-5:** With `bundle_claim` unset the Job has no bundle volume, mount, or `FLEET_BUNDLES`; with it set it has the claim volume, the agent-only mount at `<host>/<url path>/<change>`, `fsGroup` and `FLEET_BUNDLES=on` — `ac14_dispatch_inputs.sh`. Every Job now also carries `FLEET_HARD_DEADLINE` (FR-12), so the Job is not byte-identical to the pre-change render; `ac32_postgres_sidecar.sh` normalises that value.
- ✅ **AC-6:** `bundle_claim` without `node_label` is refused by dispatch, naming both settings — `ac14_dispatch_inputs.sh`.
- ✅ **AC-7:** A fully failed push writes `work.base` and `work.bundle` and records `bundle=saved`; no claim records `bundle=off`; a configured claim with a missing or read-only folder records `bundle=none` — `ac41_bundles.sh`, `ac42_bundles_real_git.sh`.
- ✅ **AC-8:** A later run resumes from a valid bundle, alone or by fast-forwarding the remote branch; a corrupt bundle, a base that is not an ancestor, or a diverged bundle is ignored with a warning — `ac41_bundles.sh`, and with real git in `ac42_bundles_real_git.sh`.
- ✅ **AC-9:** A good push removes the pair only when the pushed HEAD holds every tip in the bundle; a bundle with commits the branch lacks is kept, and a later failed push sets it aside as `kept-<n>` — `ac41_bundles.sh`, `ac42_bundles_real_git.sh`.
- ✅ **AC-10:** `doctor` prints the `bundles` line in every state, including a label that matches no node, several nodes, or a node other than the claim's — `ac16_doctor.sh`.
- ✅ **AC-11:** `kubectl apply --dry-run=client -f plugins/specclaw-fleet/k8s/bundles-pvc.yaml --context rancher-desktop` printed `persistentvolumeclaim/fleet-bundles created (dry run)`; README and setup skill describe `bundle_claim`, `push_attempts` and the `node_label` requirement.
- ⚠️ **AC-12:** UNVERIFIED. A forced push failure and a resume on a real cluster need a published image with this change. Not run.

## Test Results

- `bash plugins/specclaw-fleet/tests/run-fleet-tests.sh` at a27e780: exit 0, "All specclaw-fleet tests passed."
- `shellcheck -x -S warning` on the changed shell files: no findings.
- `specclaw-verify size`: 270 production lines against origin/main (cap 400); over half the cap.
- Bundle functions run against real git in `ac42_bundles_real_git.sh` (the rest of the suite stubs git).

## Issues Found

1. **AC-12 not run.** An operator must apply `bundles-pvc.yaml`, set `bundle_claim` and `node_label`, force a push failure, confirm a bundle is left, then run a retry and confirm a pull request opens. This also settles whether the kubelet makes the `subPath` folder writable for uid 1000 under `fsGroup`.
2. **Clock assumption.** `FLEET_HARD_DEADLINE` is stamped from the dispatching machine's clock and compared with the node's; they must agree to within about a minute.
3. **Open minors** (in `follow-ups.md` and the round files): a crash between the two renames in `save_bundle`; `_git` path segments; untimed `git bundle verify` and ancestor checks on the failure path; fixed temp names if two pods for one change ever ran at once; Azure DevOps org and project casing in the bundle folder name.
4. **Scope grew during review.** The spec's file map was extended with `image/entrypoint.sh`, `lib/dispatch.sh` and `tests/cases/ac42_bundles_real_git.sh`, and FR-7a and FR-12 were added.

## Summary

**Passed:** 11/12 criteria (AC-12 unverified)
**Failed:** 0/12
**Verdict:** PARTIAL

**Code Review:** CHANGES_REQUESTED at 7b24de0 (1 BLOCK, 2 WARN, 4 NOTE); the BLOCK and both WARNs are fixed and covered by tests. Not re-run by the code-reviewer agent after the fixes.
Review: CLEAN — 11 rounds, final pass a27e7806e5, models sonnet/opus; last round 0/0/2 b/M/m
