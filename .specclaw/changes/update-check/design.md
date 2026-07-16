# Design: Plugin Update Check

**Change:** update-check
**Created:** 2026-07-16

## Technical Approach

Single self-contained script, one wiring line in the status skill. Flow:

```
gate (plugin.update_check != false)
  → local version  (SCRIPT_DIR/../.claude-plugin/plugin.json)
  → remote version (--remote-version | fresh cache | curl raw marketplace.json, main then master)
  → numeric semver compare → one line or silence
```

Repo derivation: `repository` field of the plugin's own plugin.json → strip protocol/host prefix (`https://github.com/`), `.git` suffix, trailing slash → `owner/repo`. Raw fetch tries `main` then `master` branch paths. specclaw entry version extracted with `sed -n '/"name": *"specclaw"/,/}/p' | grep '"version"'`.

Cache: `<specclaw_dir>/.update-check` containing `<epoch> <remote_version>`. Read: if `now - epoch < 86400`, use cached version, skip network. Write: after any successful fetch. `--force` bypasses read (still writes). `--remote-version` bypasses both (pure compare, for tests).

Compare: split both versions on `.`, pad to 3 components with 0, numeric per-component. Strictly greater → notify.

## Architecture

No interactions with other scripts. Status skill runs it fire-and-forget:

```
skills/status/SKILL.md: run `specclaw-check-update .specclaw`; if it printed a line, show it after the dashboard.
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-check-update` | create | Gate, cache, fetch, compare, notify |
| `plugins/specclaw/skills/status/SKILL.md` | modify | Run check, surface line |
| `plugins/specclaw/templates/config.yaml` | modify | `plugin:` block with `update_check: true` |
| `plugins/specclaw/tests/run-parser-tests.sh` | modify | Case 8: compare/gate/silence/cache asserts (offline) |
| `README.md`, `CHANGELOG.md`, version files | modify | FR8 (version stays 0.5.1 — single release batch) |

## Data Model Changes

- Config: `plugin.update_check` (bool, default true).
- New untracked state file `.specclaw/.update-check` (`<epoch> <version>`); recommended gitignore.

## API Changes

New script CLI only. Exit 0 in every path except usage error.

## Key Decisions

1. **Explicit surface only** — check lives in `/specclaw:status`; lifecycle commands stay network-free (latency + trust).
2. **marketplace.json as source of truth** — it's what `/plugin` installs from; plugin.json in-repo could drift mid-release.
3. **Fail-silent everywhere** — a notifier that can break a workflow is worse than no notifier.
4. **`--remote-version` test hook** — makes core logic testable with zero network dependence in CI.

## Grounding sources

- `plugins/specclaw/.claude-plugin/plugin.json` — `"repository": "https://github.com/chan4lk/specclaw"` (repo derivation source).
- `.claude-plugin/marketplace.json` — plugins-array shape the extractor parses.
- `plugins/specclaw/bin/specclaw-update-context` — precedent for "always exits 0, non-blocking" auxiliary scripts.

## Risks & Mitigations

- **GitHub raw latency/outage** → 5s curl cap, daily cache, silent failure.
- **Version-parse drift if marketplace.json format changes** → extractor anchored on the specclaw name block; parse failure = silence, never a wrong nag.
- **Privacy perception** → plain GET of a public file, no identifiers; config off-switch documented.
