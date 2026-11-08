# Code Review Report: 052-fleet-setup-and-run-skills

**Reviewed:** 2026-11-07
**Model:** claude-sonnet-5-5
**Verdict:** CHANGES_REQUESTED

## Summary

12 findings: 2 BLOCK, 6 WARN, 4 NOTE
D8 applied (design.md present); D9 not checked beyond the focus list.

## Findings

### [BLOCK] plugins/specclaw-fleet/lib/podspec.sh:3-6 — Security (YAML injection)
**Problem:** `F_CLAUDE_VERSION` is validated only inside `if [[ "$F_AGENT" == claude ]]`. For codex jobs, `FLEET_CLAUDE_VERSION` is unvalidated, yet `lib/manifest.sh` renders it as `{name: FLEET_CLAUDE_VERSION, value: "$F_CLAUDE_VERSION"}` inside double quotes. A value such as `x"}, {name: FLEET_COMMIT, value: "evil` adds or overrides env entries in the Job. The Job runs the agent with `--dangerously-bypass-approvals-and-sandbox`. In the hosted pipeline this variable comes from pipeline config. `ac14` only tests the empty value for codex (`codex_free`), so the test never exercises this path.
**Fix:** Validate whenever the value is non-empty: `[[ -z "$F_CLAUDE_VERSION" || "$F_CLAUDE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]`. Keep the "required" check for claude. Add a test with `FLEET_DEFAULT_AGENT=codex FLEET_CLAUDE_VERSION='x"}'`.

### [BLOCK] plugins/specclaw-fleet/image/Dockerfile:8-9,16-18 — Security (supply chain)
**Problem:** The seed stage runs `curl -fsSL -o /tmp/claude "https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/..."; chmod +x /tmp/claude`, then executes it. The binary is never checked against a checksum or the GPG-signed manifest. The runtime path is verified, but the build-time path is not. That build-time binary writes `/opt/fleet/home-seed` (plugin installs, config), which the final stage copies with `COPY --from=seed --chown=1000:1000`, and it also runs plugin install code. A compromised release or proxy at build time puts attacker-influenced state into every pod's home seed. The claim of "verified Claude" therefore has a hole.
The binary itself does not reach the final image or its layers: only `/opt/fleet/home-seed` is copied. That part is fine. `CLAUDE_CODE_VERSION` is also a second version pin that can drift from the runtime `FLEET_CLAUDE_VERSION`.
**Fix:** Run the same verification in the seed stage. Install `gnupg jq`, copy `claude-release.asc` and `claude-fetch.sh` into the stage, and source and call `fetch_claude` with `HOME` set. Or fetch the manifest and signature, check them with gpg, and compare sha256 and size. Also confirm that nothing under `home-seed` embeds the binary or a version-specific path (for example `ls -R /opt/fleet/home-seed | grep -i claude` as a build assertion). Add a test that the seed stage is no longer an unchecked `curl`.

### [WARN] plugins/specclaw-fleet/image/claude-fetch.sh:15-17 — Security (signature check)
**Problem:** `grep -q "^\[GNUPG:\] VALIDSIG <fpr> "` matches field 1 of VALIDSIG, which is the fingerprint of the key that actually signed, possibly a subkey. The primary-key fingerprint is field 10. Pinning the primary FPR to field 1 works only if the primary key signs. If Anthropic signs with a subkey, every fetch fails closed. Also, gpg emits `VALIDSIG` for expired and revoked keys alongside `EXPKEYSIG`/`REVKEYSIG`. This check does not reject those, and the key file is never checked for expiry or revocation.
**Fix:** Also require `GOODSIG`, and reject `EXPKEYSIG|REVKEYSIG|ERRSIG`. Read the primary FPR from the last VALIDSIG field with `awk '$2=="VALIDSIG"{print $NF}'`. Add tests with an expired key and a revoked key.

### [WARN] plugins/specclaw-fleet/image/claude-fetch.sh:35-37 — Security (rollback)
**Problem:** The signed manifest's `.version` is never compared with `FLEET_CLAUDE_VERSION`. An attacker who can replace the response at `$base/…` (proxy, mirror, `FLEET_CLAUDE_RELEASES`) can serve an older, still validly signed manifest and binary from a different release under the pinned version's path. That installs a known-vulnerable Claude binary and passes all checks. The test fixture sets `version: "9.9.9"` but never tests a mismatch.
**Fix:** `[[ "$(jq -r .version "$dir/manifest.json")" == "$FLEET_CLAUDE_VERSION" ]] || return 1`, plus a test case.

### [WARN] plugins/specclaw-fleet/image/claude-fetch.sh:38-42 — Correctness (partial files)
**Problem:** If `curl -fsS -m 900 -o "$bin/claude.part" ...` fails or times out, the function returns 1 without removing `claude.part`. The tests check that no `.part` file remains only for the checksum/size failures; no case covers a failed download. There is also no `--max-filesize "$size"` bound, so a hostile proxy can stream data until the 900 s timeout and fill the pod's ephemeral storage. The bound can be set only after the manifest is verified. Using it is safe, because `size` comes from the signed manifest.
**Fix:** `curl ... --max-filesize "$size" -o "$bin/claude.part" ... || { rm -f "$bin/claude.part"; return 1; }`.

### [WARN] plugins/specclaw-fleet/lib/trigger.sh:19-23,26-27 — Design (refusal paths)
**Problem:** `trigger_gates` calls `trigger_work_item`, which runs `azdo_issue create`, before the assignee, consent and credential gates. With `--create`, a later refusal (no assignee, consent missing, no credential) leaves a created work item behind. That is an external side effect on a refusal path. The spec states that refusal paths are side-effect free. `ac17` checks refusals only without `--create`, so this is not covered.
**Fix:** Run the read-only gates first (proposal, vault, then the gates that need the work item once it exists). Or document that `--create` is an explicit opt-in to side effects and test that case.

### [WARN] plugins/specclaw-fleet/lib/trigger.sh:16 — Security (code execution)
**Problem:** `set -a; . "$SPECCLAW_DIR/.env"; set +a` sources the repo-local `.env` as shell. Anything that can write `.specclaw/.env` (including a cloned or checked-out branch) gets code execution in the operator's shell, with their az and kubectl credentials. Nothing else in `lib/` does this. The setup skill also makes the operator create this file.
**Fix:** Parse it as data: `while IFS='=' read -r k v; do [[ "$k" =~ ^[A-Z_][A-Z0-9_]*$ ]] && export "$k=$v"; done < file`. Allow only `AZDO_*` keys.

### [WARN] plugins/specclaw-fleet/pipelines/dispatch-hosted.yml:28 — Security (pinned ref)
**Problem:** `git clone --depth 1 --branch "$(fleetSpecclawRef)" https://github.com/chan4lk/specclaw.git` with `fleetSpecclawRef: fleet-v0.8.9` pins to a git tag. Tags are mutable and nothing verifies the clone. The cloned code then runs inside the `AzureCLI@2` task, with the Azure service connection and `System.AccessToken`. Anyone who can move that tag, or compromise the repo, runs code with the pipeline's credentials. The step title says "pinned ref" and the test (`hosted_ok`) only greps for the clone line.
**Fix:** Pin to a commit SHA, `git fetch --depth 1 origin <sha> && git checkout FETCH_HEAD`, or check `git rev-parse HEAD` against a `fleetSpecclawSha` variable. Document that the image tag and the ref must move together.

### [WARN] .github/workflows/fleet-image.yml:8-10,32-36,43-45 — Security (tag handling)
**Problem:** (a) `inputs.tag` is passed through `env` (good, no shell injection) but is not validated. The tag can be `latest`, or a version that already exists, and the push overwrites it. The pipeline template pins `ghcr.io/.../specclaw-fleet:0.8.9` by tag, not digest, so an overwrite silently changes what pods run. (b) `workflow_dispatch` runs from any branch, so a branch build can overwrite a release tag. (c) `build-args: CODEX_VERSION=${{ inputs.codex_version ... }}` is an unvalidated multi-line field, so a newline can inject extra build args. (d) The actions are pinned by major tag, not SHA, in a job holding `packages: write`.
**Fix:** Validate with `[[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]` and the codex version similarly. Restrict dispatch to `refs/heads/main` or tags. Output the digest and pin the pipeline by digest, or at least by tag with the overwrite risk documented. Pin actions to SHAs.

### [NOTE] plugins/specclaw-fleet/lib/doctor.sh:13 and plugins/specclaw-fleet/lib/doctor-checks.sh:3 — Correctness (errors vs answers)
**Problem:** `dk` discards stderr, so a forbidden or timeout error is reported as "missing X: apply …", which sends the operator to re-apply manifests when the real problem is access. It is never reported as ok, which is the important part. Doctor is read-only: only get, show and list calls, plus a HEAD request to GHCR (`check_image`). The only non-ok-and-non-fail result is `return 2` (skip).
**Suggestion:** Print the first line of stderr after the "missing" line. Consider exiting non-zero for "skip image" when `FLEET_IMAGE` is unset, since an unchecked image today yields "all checks ok" and `ac16` asserts exactly that for non-GHCR images.

### [NOTE] plugins/specclaw-fleet/lib/doctor-azure.sh:4,10 — Correctness (skipped as ok)
**Problem:** `check_image` with `FLEET_IMAGE` unset prints `skip image: only ghcr.io images are checked (unset)` and returns 2. `fleet_doctor` counts only rc 1, so `doctor: all checks ok` is printed with the image unchecked. `check_vault` proves only that the vault exists, not that the dispatch identity can read secrets.
**Suggestion:** Make "unset" rc 1 (a real gap) and keep the skip only for explicit non-GHCR images.

### [NOTE] plugins/specclaw-fleet/image/claude-fetch.sh:15,17 — YAGNI
**Problem:** `FLEET_CLAUDE_KEY` and `FLEET_CLAUDE_FPR` let anything that sets pod env replace the trust anchor. They exist only for tests. Pod env is rendered by the dispatcher, so the exposure is small today, but it is a trust-anchor override shipped in production code.
**Suggestion:** Keep it for tests, but make the production entrypoint `unset FLEET_CLAUDE_KEY FLEET_CLAUDE_FPR FLEET_CLAUDE_RELEASES`. The skills do not document these.

### [NOTE] plugins/specclaw-fleet/skills/setup/SKILL.md, skills/run/SKILL.md — Accuracy
**Problem:** Matches the code overall. The run skill's exit table says "1, `pass --create`" and so on, and those match `trigger.sh`. Two gaps: it does not say that `--create` can leave a work item behind after a refusal (see the WARN above), and `--retry` clears both tags only after the gates pass, so a refused retry does not clear them. The setup skill's isolation, ask-first and no-secrets guidance is sound. It tells the operator to put a PAT into `.specclaw/.env`, which `trigger` then sources as shell (see the WARN above).
**Suggestion:** Document both behaviours, and warn that `.env` must contain plain `KEY=value` lines.

## Test quality

- `ac13` proves tampered, impostor, bad sum, bad size, missing platform and a bad version string. It does not cover an expired or revoked key, a manifest/version mismatch, a failed or truncated download leaving `claude.part`, or the seed stage of the Dockerfile. `image_clean` greps for strings only, such as the fingerprint appearing anywhere in the Dockerfile.
- `ac14` does not test a malformed `FLEET_CLAUDE_VERSION` for a codex agent, which is the injection above.
- `ac15` checks structure via grep and YAML parsing. It cannot prove that the pinned ref is verified.
- `ac16` read-only check uses a grep of stub calls for verbs. That is acceptable. It does not cover the `skip` exit.
- `ac17` covers the refusal gates without `--create`, the happy paths and `--retry`. It does not cover `--create` followed by a refusal, nor an az or azdo error being read as an answer (only `WI_UPDATES=FAIL` is tested).

## Verdict Rationale

Fetch-and-verify logic at pod runtime is largely sound: it checks the version string, the GPG signature (via a throwaway keyring, cleaned up), the checksum and the size, it renames only after the checks pass, and no claude binary reaches the final image. Two issues block approval. The seed stage downloads and executes an unverified Claude binary at build time, and its output is copied into every image. The codex path skips validation of `FLEET_CLAUDE_VERSION`, which is rendered into the Job YAML. Several WARNs (signature semantics for expired keys, manifest/version rollback, `--create` side effects, `.env` sourcing, tag-pinned clone, workflow tag handling) should be fixed before release. Fix the two BLOCKs, then re-review.
