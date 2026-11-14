# Code Review Report: 049-fleet-runner-dispatch

**Reviewed:** 2026-11-07
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

14 findings: 0 BLOCK, 8 WARN, 6 NOTE

D9 skipped: no `files:` declared in tasks.md. D8 checked against design.md and spec.md.

Credential flow Key Vault -> per-Job Secret -> pod -> codex write-back is sound. The vault-writer secret is mounted only into the post-agent container. The credential never reaches argv, the manifests or the logs. The base64 temp file is mode 0600 and is removed by an EXIT trap. The `login` temp dir is 0700 and is removed by an EXIT trap. The Secret is owned by the Job. YAML interpolation goes through `jq` `yaml_str`, and the remaining unquoted values are generated, validated or hex.

## Findings

### [WARN] plugins/specclaw-fleet/lib/launch.sh:5 — Correctness (set -e orphans the Job)
**Problem:** `uid="$(kubectl -n "$F_NS" get job "$F_JOB" -o jsonpath='{.metadata.uid}')"` runs under `set -e` outside any conditional. The same goes for the base64 write on line 6 and the `attempt=` read on line 18. If any of them fails after `kubectl create` of the Job, the script exits without reaching the rollback on lines 7-10. The Job is left with no Secret. Its pod sits in ContainerCreating until the deadline. A codex assignee is then counted busy by `codex_busy`, because `.status.failed` may never be set for a pod that never ran. The spec edge case "Secret fails after Job -> delete Job" is only covered for the `render_secret | kubectl create` failure.
**Fix:** `uid="$(kubectl ... )" || uid=""` so the existing `-z "$uid"` branch rolls back. Test that branch too.

### [WARN] plugins/specclaw-fleet/image/entrypoint.sh:63 — Correctness (clone failure never reaches the work item)
**Problem:** `clone || { record state=failed exit=clone-failed; finish 2; }`. `record` calls `specclaw-azdo-issue fields "$REPO/.specclaw" ...`, and the tool dies with "Change not found" when `$CHANGE_DIR` is absent, which is the case after a failed clone. The failure is swallowed into a warning and the work item stays `Dispatched`. `on_term` during `clone` has the same problem. `on_term` is also deferred until the foreground `git clone` returns.
**Fix:** Run `record` for pre-clone failures against a minimal stub `.specclaw` dir, or give `fields` a config path/env override. Add a test for the clone-failed path.

### [WARN] plugins/specclaw-fleet/k8s/rbac.yaml:16-18 — Security (least-privilege claim is bypassable)
**Problem:** `resources: ["secrets"] verbs: ["create"]` plus `jobs: create` lets the dispatcher create a Job whose pod mounts or `envFrom`s any Secret in the namespace. That includes `fleet-vault-writer` and `fleet-azdo`. "Can never read the namespace's other Secrets" (FR-9) holds only for the API verbs. The dispatcher is effectively a secret reader and can run arbitrary pods.
**Fix:** Document the residual risk in the README. Better, add a ValidatingAdmissionPolicy that pins Job pod specs to the expected image, `envFrom` names and volumes. Alternatively, move `fleet-vault-writer` and `fleet-azdo` to a namespace the dispatcher cannot target.

### [WARN] plugins/specclaw-fleet/lib/manifest.sh:67 — Security (vault-writer scope)
**Problem:** `envFrom: [{secretRef: {name: fleet-vault-writer}}]`. One service principal can write every `codex-auth-*` secret, while the per-user scoping the design stresses is at secret level. If the SP is vault-wide Secrets Officer, any compromise of the writeback container, or of the Job-creation path above, can overwrite another user's credential.
**Fix:** State the required SP role scope in the README. Prefer `Key Vault Secrets Officer` limited to the `codex-auth-*` secrets, or per-Job tokens.

### [WARN] plugins/specclaw-fleet/lib/manifest.sh:19-33 — Correctness (write-back lost on deadline)
**Problem:** `writeback` is a regular container, so it starts only after the init `agent` exits. When `activeDeadlineSeconds` fires, the pod is terminated. The init container traps TERM, but the pod then never starts the writeback container. Codex rotates refresh tokens, so a deadline-killed run can invalidate the stored `auth.json`. The user must re-login with no signal about why.
**Fix:** Do the write-back inside the entrypoint `on_term` path for codex, or make `writeback` a sidecar that waits on `$STATUS/exit`. Otherwise document the limitation in the README.

### [WARN] plugins/specclaw-fleet/pipelines/dispatch.yml:45 — Correctness (missed approvals, unsafe splitting)
**Problem:** `for f in $(git diff --name-only HEAD^1 HEAD -- ...)` compares only HEAD against its first parent. A push, or a batched CI trigger, with several commits misses an approval made in an earlier commit. The change then never dispatches. `$(...)` word-splits and globs, which breaks NFR-4 ("change names are opaque") for names containing whitespace. `${{ parameters.vault }}` is also template-expanded into the script text.
**Fix:** Diff `$(Build.SourceVersion)` against the trigger's previous commit, or loop `git log` over the push range. Use `while IFS= read -r f; do ...; done < <(git diff -z ...)`. Pass the vault through `env:`.

### [WARN] plugins/specclaw-sync/bin/specclaw-azdo-issue:431 — Correctness (comment lost on PATCH failure)
**Problem:** `ado_patch_json ... || die "ADO field update failed ..."` exits before line 433's `cmd_comment`. A rejected state transition or field is exactly when the record matters most. FR-8 says "always adds one comment". Callers then only see `warn "could not update the work item"`, and the refusal reason is lost.
**Fix:** Post the comment first, or on PATCH failure post it with a "(field update failed)" line, and then fail.

### [WARN] plugins/specclaw-fleet/tests/cases/ — Test quality (spec edge cases untested)
**Problem:** There is no test for the following.
- Secret-create failure causing a Job delete (spec edge case, and the finding above).
- The SIGTERM `deadline` trap.
- The clone-failed path.
- The codex branch of the entrypoint (`seed_codex`, `seed.sha`). The write-back test seeds `seed.sha` by hand, so the two halves are never connected.
- A write-back PUT failure (`rc != 0 ? rc : 3`).
- Change names with metacharacters, or a long name (the AC edge case).
**Fix:** Add small cases for each. The `kubectl` stub makes the rollback test cheap, and the `sha256sum` and `exit` assertions in the existing cases make the rest easy to extend.

### [NOTE] plugins/specclaw-fleet/tests/cases/ac7_entrypoint.sh:31 — Test quality (vacuous assertion)
**Problem:** `no_token_in_url` greps the git stub's argv for `pat-secret`. The header is passed through `GIT_CONFIG_VALUE_0` in the environment, so the argv can never contain the token. The test passes even if the `Authorization` header is not set, or is set wrongly. Make the stub also record `$GIT_CONFIG_VALUE_0` and assert the header, so the AC7 clone claim is proved.

### [NOTE] plugins/specclaw-fleet/tests/cases/ac4_gates.sh:12-29 — Test quality (refusal reason not asserted)
**Problem:** `refused` is just `rc != 0 && nothing_applied`. Any earlier failure, such as a stub typo or a missing config, satisfies AC4a/b. Assert the expected message in `$TMP/out` for each case. For c-f, also assert the `exit=refused: ...` text, not only `state=failed`.

### [NOTE] plugins/specclaw-fleet/tests/cases/ac10_manifests.sh:8-19 — Test quality (text-grep tests)
**Problem:** `rules()` and `pods_default_deny` grep YAML as text, for example `grep -c "resources:" == 2`. This is brittle: reordering or reformatting the YAML breaks them. Parsing with `python3 -c 'import yaml'` would be stronger, but is only worth it if PyYAML is already a CI dependency.

### [NOTE] plugins/specclaw-fleet/lib/launch.sh:6-7 — YAGNI
**Problem:** The `FLEET_B64` temp file and its trap are not needed. The base64 value is already a shell variable, and the `$(cat ...)` round-trips it through disk. Also `die ... (Job removed)` prints that even when the `|| true` delete failed.
**Suggestion:** `render_secret "$(printf '%s' "$F_CREDENTIAL" | base64 | tr -d '\n')" "$uid" | kubectl ...`, and drop the trap.

### [NOTE] plugins/specclaw-fleet/lib/workitem.sh:34 — Bash pitfall
**Problem:** `printf | tr | sed | grep -qxF ... && return 0` under `pipefail`. `grep -q` can exit early and make an upstream stage SIGPIPE, so the pipeline returns 141 and consent reads as false. This is practically impossible with tag-sized input, but it is the classic trap.
**Suggestion:** `grep -xF fleet:auto >/dev/null`, or feed with `<<<"$tags"`.

### [NOTE] plugins/specclaw-fleet/lib/dispatch.sh:29-40 — Behaviour
**Problem:** `--dry-run` still fetches the real credential from Key Vault and runs `refuse`. A dry run then mutates the work item (`state=failed`) and posts a comment. `codex_busy` also has a check-then-create race for two concurrent pipeline runs for the same assignee. Skip `refuse` side effects when `F_DRY_RUN=1`, and note the race in the README.

### [NOTE] .claude-plugin/marketplace.json + plugins/specclaw-fleet/.claude-plugin/plugin.json — Version bump
**Problem:** The version is `0.8.7`, the same as main, and a new plugin was added. CLAUDE.md requires a patch bump (`0.8.8`) across all plugins and marketplace entries before the PR. The versions are consistent now, so this is only a reminder.

## Verdict Rationale

There are no BLOCK findings. Credential handling is correct: no secret reaches argv, manifests, logs or JSON, the Secret is Job-owned, and the vault credential is isolated to the write-back container. The temp files and the `login` dir are cleaned on exit paths. Manifest rendering is injection-safe. The warnings are real but bounded. The main ones are the `set -e` rollback gap, the clone-failure record that never lands, the dispatcher's effective Secret access via Job creation, the lost write-back on deadline, the pipeline's single-commit diff, and untested spec edge cases. The warnings should be fixed or documented before merge. Core `plugins/specclaw/` is untouched apart from the one permitted inventory line.
