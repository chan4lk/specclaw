# Spec: Plugin Update Check

**Change:** update-check
**Created:** 2026-07-16
**Status:** 🟡 Draft

## Overview

Quiet, config-gated update notifier: `/specclaw:status` tells the operator when a newer plugin version is published, once per day at most, failing silently on any error.

## Requirements

### Functional Requirements

- **FR1 — Script.** `specclaw-check-update <specclaw_dir> [--force] [--remote-version X]`: installed version from the plugin's own `.claude-plugin/plugin.json` (relative to the script); published version from `https://raw.githubusercontent.com/<owner>/<repo>/<main|master>/.claude-plugin/marketplace.json` where `<owner>/<repo>` is parsed from plugin.json's `repository` URL; the specclaw entry's `version` field is extracted jq-free.
- **FR2 — Cache.** Result cached in `<specclaw_dir>/.update-check` (`<epoch> <version>`); cache younger than 86400s short-circuits the network unless `--force`.
- **FR3 — Compare.** Component-wise numeric semver comparison. Remote > local → print exactly one `⬆ specclaw ... /plugin update specclaw` line to stdout. Equal/older → no output.
- **FR4 — Gate.** `plugin.update_check` config value `false` → exit 0 immediately, no network, no output. Absent = `true`.
- **FR5 — Fail-silent.** Missing curl, network failure, unparseable response, missing plugin.json → exit 0, no stdout output (stderr allowed for `--force` diagnostics only).
- **FR6 — Test hook.** `--remote-version X` skips network and cache entirely and compares directly.
- **FR7 — Status wiring.** `/specclaw:status` SKILL runs the script and surfaces its output line when non-empty.
- **FR8 — Docs.** Config template `plugin:` block with `update_check`; README section (incl. gitignore advice for the cache file); CHANGELOG bullet under 0.5.1 (single release with the open PR batch).

### Non-Functional Requirements

- **NFR1** — Plain bash + coreutils + curl (optional); jq-free; BSD/GNU safe.
- **NFR2** — Never blocks: `curl --max-time 5`; no retries.
- **NFR3** — No behavior change anywhere when `update_check: false` or script absent.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- [ ] **AC1** — `--remote-version` newer than installed → exactly one stdout line containing the remote version, installed version, and `/plugin update specclaw`.
- [ ] **AC2** — `--remote-version` equal and older → empty stdout, exit 0.
- [ ] **AC3** — Config `plugin.update_check: false` + newer `--remote-version` → empty stdout, exit 0 (gate beats hook).
- [ ] **AC4** — Nonexistent-domain repository URL (network guaranteed to fail) → empty stdout, exit 0, under ~6s.
- [ ] **AC5** — Cache file written on a successful real check path (structure `<epoch> <version>`); fresh cache short-circuits (verifiable via `--force` semantics: without force + fresh cache, no curl call — asserted by cache-only test with unreachable network still producing a verdict from cache).
- [ ] **AC6** — status SKILL.md documents running the check and surfacing the line.
- [ ] **AC7** — Suite passes with new cases; `bash -n` clean.
- [ ] **AC8** — Template has `plugin.update_check`; README documents behavior + cache gitignore advice; CHANGELOG updated; version 0.5.1 both files.

## Edge Cases

- Version strings with unequal component counts (0.5 vs 0.5.1) → missing components treated as 0.
- plugin.json `repository` with `.git` suffix or trailing slash → normalized.
- marketplace.json listing multiple plugins → specclaw entry's version specifically extracted.
- Corrupt cache file → ignored, treated as stale.

## Dependencies

None new; curl optional.

## Notes

Explicit-surface-only design: check runs where the user asks for status, never ambiently in build/verify/pr.
