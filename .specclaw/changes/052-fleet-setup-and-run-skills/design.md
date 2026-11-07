# Design: specclaw-fleet setup and run skills

**Change:** 052-fleet-setup-and-run-skills
**Created:** 2026-11-07

## Technical Approach

The work builds on 049's structure: one Bash router, small sourced libs, and image scripts sourced by the entrypoint. New logic gets its own file, so every file stays at 80 lines or fewer.

- **Claude fetch.** `image/claude-fetch.sh` runs verify first, download second. GPG uses a temp homedir with the baked key. The signature must report `VALIDSIG <pinned fpr>` on `--status-fd`. The binary is written to `$HOME/.fleet/bin/claude.part`, checked for SHA256 and size, then renamed into place.
- **doctor.** It is a table of check functions. Each prints one line and returns 0, 1 or 2. Only `kubectl get`, `az ... show/list`, and `curl` GETs (the GHCR anonymous token plus the manifest HEAD) are used.
- **trigger.** It reuses `workitem.sh` and `consent.sh` (assignee, tags, consent, credential). It adds `azdo_issue create`, `untag` and `az pipelines run`.
- **Hosted pipeline.** It is a second template file. It doesn't share YAML with `dispatch.yml`: the hosted file adds two steps, and its dispatch script is otherwise identical.

## File Changes Map

| File | Action | Description |
|---|---|---|
| `plugins/specclaw-fleet/image/Dockerfile` | modify | remove claude download; add gnupg, the baked key with a fingerprint check, and `DISABLE_UPDATES` |
| `plugins/specclaw-fleet/image/claude-release.asc` | create | Anthropic's public release key (public, verified fingerprint) |
| `plugins/specclaw-fleet/image/claude-fetch.sh` | create | `fetch_claude`: verify, download, check, time |
| `plugins/specclaw-fleet/image/entrypoint.sh` | modify | call `fetch_claude` for claude jobs; per-run budget wording |
| `plugins/specclaw-fleet/image/bin/claude` | modify | default real binary is `$HOME/.fleet/bin/claude` |
| `plugins/specclaw-fleet/lib/dispatch.sh` | modify | validate `FLEET_CLAUDE_VERSION`, `FLEET_IMAGE_PULL_SECRET`, `FLEET_NODE_LABEL` |
| `plugins/specclaw-fleet/lib/manifest.sh` | modify | emit `FLEET_CLAUDE_VERSION` and the optional pod-spec fragments |
| `plugins/specclaw-fleet/lib/podspec.sh` | create | the optional fragments (`imagePullSecrets`, `nodeSelector`, `tolerations`), keeping `manifest.sh` at 80 lines or fewer |
| `plugins/specclaw-fleet/lib/doctor.sh`, `lib/doctor-checks.sh` | create | runner plus check table |
| `plugins/specclaw-fleet/lib/trigger.sh` | create | gates, retry, queue or dispatch |
| `plugins/specclaw-fleet/bin/specclaw-fleet` | modify | route `doctor` and `trigger` |
| `plugins/specclaw-fleet/pipelines/dispatch-hosted.yml` | create | hosted-agent template |
| `.github/workflows/fleet-image.yml` | create | multi-arch GHCR build and push |
| `plugins/specclaw-fleet/skills/setup/SKILL.md`, `skills/run/SKILL.md` | create | the two skills |
| `plugins/specclaw-fleet/README.md` | modify | setup points to the skill; document `doctor` and `trigger`; hosted mode |
| `plugins/specclaw-fleet/tests/cases/ac13_*`..`ac17_*`, `tests/lib/gpg-env.sh` | create | tests |
| `.github/workflows/ci.yml` | modify | nothing new: `run-fleet-tests.sh` already runs every case file |

## Key Decisions

- **Bake the public key; don't fetch it.** Fetching the key from the host whose files it verifies adds nothing. A baked key plus a pinned fingerprint is the trust anchor, and the build itself fails if the key ever changes.
- **Version comes from dispatch, not the image.** The image is generic and public, and each Job names the Claude version it runs. A bump is a variable change, not an image rebuild.
- **Tests use a throwaway GPG key.** CI never depends on Anthropic's servers, and the signature logic is exercised for real.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Per-pod 340 MB download adds latency and Azure-side egress | measured per run (`claude_fetch_s`); a node-level cache is a follow-up if the numbers warrant it |
| Release key rotation | the build fails at the fingerprint check; rotating means updating the pinned fingerprint in one place |
| `doctor` drifts into fixing things | a test fails on any mutating call |
