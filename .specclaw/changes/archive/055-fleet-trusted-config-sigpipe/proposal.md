# Proposal: specclaw-fleet trusted-config check dies with SIGPIPE (exit 141)

**Created:** 2026-11-09
**Status:** 🟡 Draft

## Problem

Every hosted specclaw-fleet pipeline run fails before it dispatches anything. demo-studio run 2472 (`feature/catalog-admin`) ended at the step "Dispatch newly approved changes" with `##[error]Script failed with exit code: 141` and no other output. No Job reached the cluster, and the feature's five work items (#216–#220) stayed `waiting`.

The cause is `plugins/specclaw-fleet/lib/settings.sh:47` in `load_fleet_settings`:

```bash
trusted="$(fleet_config_pairs "$FLEET_TRUSTED_CONFIG" | awk -F'\t' -v k="$key" '$1 == k { print $2; exit }')"
```

`awk` exits on the first matching key. `fleet_config_pairs` is a bash `while … printf` loop that is still writing the remaining keys, so its next `printf` gets SIGPIPE. Under `set -euo pipefail` (`bin/specclaw-fleet:2`) the command substitution returns 141, and `set -e` kills the process without a message.

- The check only runs when `FLEET_TRUSTED_CONFIG` is set. The pipeline template always sets it; a laptop never does. So `feature plan`, `optin` and `status` work locally, and every pipeline run fails: `main` (`dispatch`) and `feature/*` (`feature advance`) alike.
- Local repro in demo-studio, at the same code as the pinned `d0af997`: `FLEET_TRUSTED_CONFIG=$PWD/.specclaw/config.yaml specclaw-fleet feature plan catalog-admin` prints nothing and exits `141`. Without the variable it exits 0.
- The first secure key in a typical `fleet:` block is `vault`, which is also the first line. That guarantees awk exits while the producer still has lines to write. `ac22_settings.sh` evidently did not hit this ordering, or the race went the other way.

## Proposed Solution

1. **Fix the reader.** Let awk consume all of its input and print the first match at the end:

   ```bash
   trusted="$(fleet_config_pairs "$FLEET_TRUSTED_CONFIG" | awk -F'\t' -v k="$key" '$1 == k && !f { v = $2; f = 1 } END { print v }')"
   ```

   Behaviour is unchanged (first match wins, and a missing key gives an empty string, which then fails the existing "differs from the trusted branch" check). Only the early exit goes.
2. **Sweep the same class of bug.** Under `pipefail`, any `producer | consumer-that-exits-early` can return 141. Replace each early-exit consumer in `plugins/specclaw-fleet` with a first-match form that does not close the pipe early. Known sites:
   - `lib/settings.sh:47`: the bug above.
   - `lib/workitem.sh:58` (`grep -oE … | head -1`), `lib/feature-graph.sh:8` and `lib/doctor-azure.sh:53` (`sed … | head -n1`). These are safe today only because the producer's output fits in one buffered write. Switch them to `grep -m1` / `sed -n '…{p;q}'` (or drop the pipe) so they don't depend on that.
3. **Regression test.** A new case in `tests/cases/ac22_settings.sh` (or `ac36_sigpipe.sh`) runs `load_fleet_settings` with `FLEET_TRUSTED_CONFIG` pointing at a `fleet:` block where the first key is a secure one followed by at least 200 more lines. It asserts exit 0 and the expected exported values, repeated 20 times so a race cannot pass by luck. A second case runs `feature plan` with `FLEET_TRUSTED_CONFIG` set, end to end.
4. **Release.** Bump the specclaw-fleet patch version. The README's pipeline template pin (`fleetSpecclawRef`) moves to the fix commit, so consumers know which SHA to pin.

## Scope

### In Scope
- `plugins/specclaw-fleet/lib/settings.sh`, `lib/workitem.sh`, `lib/feature-graph.sh`, `lib/doctor-azure.sh`.
- Regression tests in `plugins/specclaw-fleet/tests/cases/`.
- Version bump and pinned-SHA note in the specclaw-fleet README / pipeline template.

### Out of Scope
- Updating the pin in consuming repos (demo-studio's `azure-pipelines/specclaw-fleet.yml`): done there, after this merges.
- Changing `set -euo pipefail` or the trusted-config design itself.
- Re-running demo-studio's `catalog-admin` feature.

## Impact

- **Size:** bounded (spike / bounded / architectural). It fixes an existing flow (`load_fleet_settings`) plus three one-line pipe sites; no new interface.
- **Files affected:** 6 (estimated)
- **Complexity:** small
- **Risk:** low. The new form returns the same values; the tests pin the behaviour. The risk of not fixing it is high: every hosted fleet run fails.

## Open Questions

- Should the pipeline step trap exit 141 and log "SIGPIPE in specclaw-fleet" so a future case is not silent? (Lean: no; fix the class instead.)
- Should a lint check (a grep in the test runner) refuse new `| head` / `awk … exit` pipes in `plugins/specclaw-fleet/lib`?

---

**To proceed:** Review this proposal and approve to begin planning.
