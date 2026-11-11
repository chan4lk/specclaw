# Verify report — 058-fleet-any-project-postgres

**Verdict:** PASS

- AC-1: pass — `tests/cases/ac7_entrypoint.sh` "R058 AC-1": dev.azure.com and legacy `<org>.visualstudio.com[/DefaultCollection]` clone URLs set AZDO_ORG/AZDO_PROJECT (any host case, `user@` ignored); GitHub and `_git`-less URLs keep the secret's. Values from either source are URL-encoded once (`url_seg`: raw space, non-ASCII, `?`, `#`, lone `%` encoded; existing `%XX` kept), AZDO_REPO too. Deviation from spec FR-1: values stay URL-encoded rather than decoded, because every in-pod consumer splices them into URLs (review round 1–2).
- AC-2: pass — `ac22_settings.sh` "R058 AC-2" (postgres_image only from the trusted branch); `ac32_postgres_sidecar.sh` refusal table (unpinned image, short digest, port 0/70000, bad user/password/db, postgres settings without an image), each naming the field, nothing applied.
- AC-3: pass — `ac32_postgres_sidecar.sh`: without postgres the Job equals the pre-058 render (a one-character mutation makes it fail); with it, `postgres` precedes `agent` in initContainers with `restartPolicy: Always`, `pg_isready` startupProbe on the port, `listen_addresses=127.0.0.1`, POSTGRES_* and agent PG* values, three emptyDir volumes, valid YAML.
- AC-4: pass — README documents `postgres_*`, the Playwright version rule and one namespace for several projects; setup skill adds the PAT note and repo-config items. Deviation: no doctor hint (doctor's fleet-azdo line only checks secret keys).

Commands (exit codes): `bash plugins/specclaw-fleet/tests/run-fleet-tests.sh` 0 · `bash plugins/specclaw/tests/shellcheck-gate.sh` 0 (no new findings) · `specclaw-build finalize` lint/build passed.
Cluster: bistec-dev-uat server v1.36.3+k3s1 (native sidecars need ≥ 1.29).
Not run: a real Job with the sidecar on the cluster (needs the 0.9.5 image published).
Screenshots: none — no UI.
Review: CLEAN — 7 rounds, final pass eb8904234b, models sonnet/opus; last round 0/0/2 b/M/m. Minors in follow-ups.md.
