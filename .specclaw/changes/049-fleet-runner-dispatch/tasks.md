# Tasks: specclaw-fleet — sandboxed K3s jobs running Claude or Codex on the assignee's own plan

**Change:** 049-fleet-runner-dispatch
**Created:** 2026-11-07
**Total Tasks:** 7

## Summary

Wave 1 lays the packaging and the single Boards writer. Wave 2 adds the credential and dispatch CLI. Wave 3 adds what runs inside the cluster, plus docs and CI.

## Tasks

### Wave 1 — packaging and Boards writer

- [x] `T1` — Scaffold `specclaw-fleet` plugin and register it in both marketplaces (AC-1)
  - Files: plugins/specclaw-fleet/.claude-plugin/plugin.json, plugins/specclaw-fleet/.codex-plugin/plugin.json, .claude-plugin/marketplace.json, .agents/plugins/marketplace.json, plugins/specclaw/tests/run-codex-plugin-tests.sh
  - Estimate: small
  - Kind: config
  - Notes: version 0.8.7 (matches all others; the PR bump happens later). Codex manifest `"skills": "./skills/"`.

- [x] `T2` — Add `specclaw-azdo-issue fields` subcommand with mapped-only PATCH plus audit comment (AC-9)
  - Files: plugins/specclaw-sync/bin/specclaw-azdo-issue, plugins/specclaw-sync/skills/azdo-issue/SKILL.md, plugins/specclaw-sync/tests/run-azdo-issue-fields-tests.sh
  - Estimate: medium
  - Kind: impl
  - Notes: map through `azdo.fleet_fields.<key>` / `azdo.fleet_states.<value>` via existing `yaml_val`; reuse `ado_patch_json` / `ado_post_json`; JSON built with python3 `json.dumps`. Test stubs `curl` and asserts the request bodies.

### Wave 2 — credentials and dispatch

- [ ] `T3` — `specclaw-fleet onboard` and `login`: per-secret RBAC, own-identity upload, no token leakage (AC-2, AC-3)
  - Files: plugins/specclaw-fleet/bin/specclaw-fleet, plugins/specclaw-fleet/tests/run-fleet-tests.sh
  - Estimate: medium
  - Kind: impl
  - Depends: T1
  - Notes: `<h>` = first 16 hex of sha256(lowercase UPN). Onboard: `az keyvault secret set` placeholder `__unset__` only if missing; `az role assignment list/create --scope <vault-id>/secrets/<name>`. Login: temp dir with trap cleanup; token passed to `az` via `--file`, never argv. Canary-token test.

- [ ] `T4` — `specclaw-fleet dispatch`: gates (a)–(f), per-Job Secret owned by Job, Job render, fields + `Dispatched`, JSON output, `--dry-run` (AC-4, AC-5, AC-6, AC-10 rendered-YAML part)
  - Files: plugins/specclaw-fleet/bin/specclaw-fleet, plugins/specclaw-fleet/tests/run-fleet-tests.sh
  - Estimate: large
  - Kind: impl
  - Depends: T2, T3
  - Notes: phase via `specclaw-validate-change … status` / state.json read-only; WI id via status.md line; WI GET for AssignedTo + Tags; codex serial via labelled-Jobs jq filter; Secret deleted if Job apply fails; safe Job name `fleet-<nnn|hash>-<rand5>`. Never interpolate change name into regex.

### Wave 3 — in-cluster, docs, CI

- [ ] `T5` — Runner image: Dockerfile, agent `entrypoint.sh`, codex `writeback.sh` (AC-7, AC-8)
  - Files: plugins/specclaw-fleet/image/Dockerfile, plugins/specclaw-fleet/image/entrypoint.sh, plugins/specclaw-fleet/image/writeback.sh, plugins/specclaw-fleet/tests/run-fleet-tests.sh
  - Estimate: medium
  - Kind: impl
  - Depends: T4
  - Notes: entrypoint unsets 4 key vars, clones with `http.extraHeader`, SIGTERM trap → `Failed`/`deadline`, always exit 0 with `/status/exit`. Writeback: sha256 compare, client-credentials token via curl, PUT secret, exit with recorded status. Tests run both scripts with stub binaries.

- [ ] `T6` — Sandbox manifests and AzDO pipeline template (AC-10 manifest part)
  - Files: plugins/specclaw-fleet/k8s/namespace.yaml, plugins/specclaw-fleet/k8s/rbac.yaml, plugins/specclaw-fleet/k8s/egress.yaml, plugins/specclaw-fleet/pipelines/dispatch.yml, plugins/specclaw-fleet/tests/run-fleet-tests.sh
  - Estimate: medium
  - Kind: config
  - Depends: T4
  - Notes: Role verbs/resources exactly FR-9; default-deny + allow DNS + proxy; Squid allowlist incl. api.anthropic.com, api.openai.com, auth.openai.com, chatgpt.com, dev.azure.com, .visualstudio.com, login.microsoftonline.com, .vault.azure.net; 169.254.169.254 excluded via ipBlock except. Tests assert structure with grep/python (no cluster).

- [ ] `T7` — Skills, README setup guide, CI registration (AC-11)
  - Files: plugins/specclaw-fleet/skills/dispatch/SKILL.md, plugins/specclaw-fleet/skills/login/SKILL.md, plugins/specclaw-fleet/README.md, .github/workflows/ci.yml
  - Estimate: small
  - Kind: docs
  - Depends: T5, T6
  - Notes: README covers vault RBAC/onboard, AzDO fields+states mapping, PAT scopes, proxy hosts + how to capture missing ones, consent tag, per-seat cost note, A1 assumption. Run shellcheck gate.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
