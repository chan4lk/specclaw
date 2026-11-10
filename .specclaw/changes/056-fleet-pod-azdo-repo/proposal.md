# Proposal: specclaw-fleet pod never sets AZDO_REPO, so the agent's pr-azdo always fails

**Created:** 2026-11-10
**Status:** 🟢 Approved (operator, 2026-11-10: "add this AZDO repo variable to the pod")

## Problem

demo-studio wave 1 of `catalog-admin` (008, 011, 012): 008 and 012 passed verify with a clean review, yet both PRs (1393, 1394) opened as drafts titled "verify did not pass". The agent logs show why: the agent ran the `specclaw-sync` `pr-azdo` skill, and `specclaw-azdo-pr` died with `AZDO_REPO not set — run: specclaw auth azdo`. The pod gets `AZDO_TOKEN`, `AZDO_ORG` and `AZDO_PROJECT` from the `fleet-azdo` secret, but nothing sets `AZDO_REPO`. With no `phases.pr.url` recorded, the pod's fallback in `image/draft-pr.sh` opened a draft PR. Outside integrate mode that fallback always opens a draft.

## Proposed Solution

`image/entrypoint.sh` exports `AZDO_REPO` as the last path segment of `FLEET_REPO_URL` (the repo the pod cloned), unless `AZDO_REPO` is already set. `specclaw-azdo-pr` takes the repo name in exactly that form (`git/repositories/${AZDO_REPO}`).

## Scope

### In Scope
- `plugins/specclaw-fleet/image/entrypoint.sh`, and a test in `tests/cases/ac7_entrypoint.sh` (with its stub in `tests/lib/entry-env.sh`).

### Out of Scope
- Making the fallback PR read the verify verdict. It is no longer the normal path once `pr-azdo` works.
- The stale change lock from `specclaw-build setup` (the agent clears it itself).
- `specclaw-build setup` cutting change branches from `main`, not from the feature ref (seen on 012).
- 011's review round 5 exiting 3 (a backend that returned no JSON).

## Impact

- **Size:** bounded
- **Files affected:** 3
- **Risk:** low. It only sets a variable that was missing, and a preset `AZDO_REPO` wins.
