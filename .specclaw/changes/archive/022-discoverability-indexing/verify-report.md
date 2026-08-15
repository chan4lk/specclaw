# Verify Report: Discoverability & indexing

**Change:** discoverability-indexing
**Date:** 2026-07-17
**Verdict:** PASS

## Acceptance criteria

| AC | Result | Evidence |
|----|--------|----------|
| AC1 — sitemap plugin + canonical URLs | ✅ PASS | `docs/_config.yml`: `plugins: [jekyll-sitemap]`, `url: https://chan4lk.github.io`, `baseurl: /specclaw` |
| AC2 — robots.txt allow-all + sitemap | ✅ PASS | `docs/robots.txt`: `User-agent: *` / `Allow: /` + `Sitemap: https://chan4lk.github.io/specclaw/sitemap.xml` |
| AC3 — llms.txt convention | ✅ PASS | `# SpecClaw` H1 + one-line blockquote summary + 3 `## ` link sections |
| AC4 — llms-full.txt expanded | ✅ PASS | Covers what-it-is, propose→plan→build→verify→pr lifecycle, install, command list, config |
| AC5 — index.md keyword-tuned, links resolve | ✅ PASS | Title + intro carry "spec-driven development", "Claude Code plugin", full lifecycle; links are absolute GitHub URLs / in-page anchors / baseurl-safe `./privacy.html` |
| AC6 — INDEXING.md checklist + drafts | ✅ PASS | Owner-only steps (Pages, homepage, Search Console, social image) + drafted awesome-list entry |
| AC7 — no plugin runtime code touched; version synced | ✅ PASS | `git diff main...HEAD` under `plugins/specclaw/` = only `plugin.json` version; both manifests at 0.5.4; CHANGELOG updated |

## Non-functional

- **NFR1** ✅ — change confined to `docs/` + version bump + CHANGELOG. No `plugins/specclaw/**` runtime code.
- **NFR2** ✅ — sitemap/robots URLs absolute and canonical.
- **NFR3** ✅ — `_config.yml` is valid YAML (parsed clean); only the GitHub-Pages-allowlisted `jekyll-sitemap` plugin added.

## Notes

Live indexing (crawl, Search Console, Pages build) is owner-only and documented in `docs/INDEXING.md` — out of scope per spec. Verification here is structural: file presence, config validity, convention conformance, and scope containment. All pass.

**Verdict: PASS** — 7/7 ACs, 3/3 NFRs.
