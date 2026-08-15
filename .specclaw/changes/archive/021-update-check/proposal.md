# Proposal: Plugin Update Check

**Created:** 2026-07-16
**Status:** 🟡 Draft

## Problem

_What problem are we solving? Why does it matter?_

Marketplace installs of SpecClaw don't surface new releases — users silently run stale versions missing fixes (this repo alone shipped 5 defect-fix releases in its history). There is no mechanism telling an operator "a newer plugin exists, update with /plugin".

## Proposed Solution

_What are we building? High-level approach._

A deliberately quiet, config-gated update check:

1. **New script `specclaw-check-update <specclaw_dir> [--force]`:**
   - Reads the installed version from the plugin's own `plugin.json`; the published version from the plugin repo's raw `marketplace.json` (repo derived from plugin.json's `repository` field — no hardcoded URL).
   - **Daily cache** in `.specclaw/.update-check` (epoch + last seen version); network touched at most once per 24h unless `--force`.
   - Numeric semver comparison; newer → prints exactly one line: `⬆ specclaw X.Y.Z available (installed A.B.C) — update: /plugin update specclaw`.
   - **Every failure is silent success** — no network, bad JSON, missing curl: exit 0, no output. An update notice must never break or delay a lifecycle command.
   - `--remote-version X` test hook (skips network) so compare logic is testable offline.
2. **Config gate:** `plugin.update_check: true` in the template; `false` = zero network calls ever.
3. **Wiring:** `/specclaw:status` runs the check and shows the line when present — explicit, user-initiated surface only. No ambient checks in propose/plan/build/verify/pr.
4. Docs: README note (incl. gitignoring `.specclaw/.update-check`), CHANGELOG.

## Scope

### In Scope
- `bin/specclaw-check-update`, config template key, status SKILL.md wiring, offline tests (compare logic + gate + silence), README + CHANGELOG + version.

### Out of Scope
- Auto-updating (users update via `/plugin update`).
- Checks inside other lifecycle skills.
- Changelog-diff display or release notes fetching.

## Impact

- **Files affected:** ~7 (estimated)
- **Complexity:** small
- **Risk:** low — additive, gated, fail-silent by design

## Open Questions

1. Cache location `.specclaw/.update-check` — commit or ignore? **Resolved:** recommend gitignore (README note); harmless if committed (one line, no secrets).

---

**To proceed:** Review this proposal and approve to begin planning.
