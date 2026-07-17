# Tasks: Discoverability & indexing (Google, GitHub, AI search)

**Change:** discoverability-indexing
**Created:** 2026-07-17
**Total Tasks:** 5

## Summary

Docs-only indexing scaffolding for the `docs/` Pages site: sitemap plugin + robots + llms.txt/llms-full.txt + keyword tuning + owner checklist, then the mandatory version bump. Wave 1 files are independent; wave 2 is the release bump.

## Tasks

### Wave 1 — Indexing artifacts (parallel, independent files)

- [x] `T1` — Enable sitemap + set canonical URLs in `_config.yml`
  - Files: `docs/_config.yml`
  - Estimate: small
  - Notes: Add `plugins: [jekyll-sitemap]`, `url: https://chan4lk.github.io`, `baseurl: /specclaw`. Keep existing YAML valid. Satisfies AC1.

- [x] `T2` — Add `robots.txt`
  - Files: `docs/robots.txt`
  - Estimate: small
  - Notes: `User-agent: *` / `Allow: /` + `Sitemap: https://chan4lk.github.io/specclaw/sitemap.xml`. No front matter (served raw). Satisfies AC2.

- [x] `T3` — Add `llms.txt` (short) and `llms-full.txt` (expanded)
  - Files: `docs/llms.txt`, `docs/llms-full.txt`
  - Estimate: medium
  - Notes: `llms.txt` = `# SpecClaw` H1 + one-line summary + `## ` sectioned links (README, docs, install, commands, license). `llms-full.txt` = expanded plain text: what it is, propose→plan→build→verify→pr lifecycle, install commands, command list, config surface. No front matter. Satisfies AC3, AC4.

- [x] `T4` — Keyword-tune `index.md` + add `INDEXING.md`
  - Files: `docs/index.md`, `docs/INDEXING.md`
  - Estimate: medium
  - Notes: Tune `index.md` title/description for search intent; ensure links are baseurl-safe (absolute GitHub URLs or `{{ site.baseurl }}`). `INDEXING.md` = owner-only checklist (enable Pages, set homepage, Search Console + submit sitemap, upload social image) + drafted awesome-list / plugin-directory submission text. Satisfies AC5, AC6.

### Wave 2 — Release

- [x] `T5` — Version bump + CHANGELOG
  - Files: `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`
  - Estimate: small
  - Depends: T1, T2, T3, T4
  - Notes: Patch bump both manifests in sync; add CHANGELOG entry. Confirm nothing under `plugins/specclaw/` else changed (AC7).

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
