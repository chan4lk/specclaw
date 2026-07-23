# Spec: Discoverability & indexing (Google, GitHub, AI search)

**Change:** discoverability-indexing
**Created:** 2026-07-17
**Status:** 🟡 Draft

## Overview

Make the SpecClaw `docs/` GitHub Pages site crawlable by search engines and citable by AI search tools. Add the standard indexing artifacts (sitemap, robots, llms.txt) and prepare external-listing submission text. Docs-only — no plugin runtime code changes.

Base site URL (default GitHub Pages): `https://chan4lk.github.io/specclaw`

## Requirements

### Functional Requirements

- **FR1** — `docs/_config.yml` enables the `jekyll-sitemap` plugin so a `sitemap.xml` is generated at the site root on build. `url` and `baseurl` are set so generated links resolve to `https://chan4lk.github.io/specclaw`.
- **FR2** — `docs/robots.txt` allows all crawlers and references the sitemap absolute URL. Served at site root.
- **FR3** — `docs/llms.txt` — a short, structured index (H1 title, one-line summary, blockquote, sectioned links) following the llms.txt convention. Points to the key pages (README, docs site, install, commands, license).
- **FR4** — `docs/llms-full.txt` — an expanded, self-contained plain-text description of SpecClaw (what it is, the lifecycle, commands, install, config surface) suitable for direct LLM ingestion.
- **FR5** — `docs/index.md` front matter / opening description tuned for search intent — keyword-clear title and description ("spec-driven development", "Claude Code plugin", "propose → plan → build → verify → pr").
- **FR6** — A maintainer checklist (`docs/INDEXING.md` or a section) listing the owner-only steps (enable Pages, set homepage URL, Google Search Console + submit sitemap, upload social image) and the drafted awesome-list / plugin-directory submission text.

### Non-Functional Requirements

- **NFR1** — No plugin runtime code (`plugins/specclaw/**`) is modified. Change is confined to `docs/` plus the standard version bump + CHANGELOG.
- **NFR2** — Generated URLs are absolute and use the canonical base; no broken/relative links in sitemap or robots.
- **NFR3** — `_config.yml` stays valid YAML and Pages-safe (only GitHub-Pages-whitelisted plugins; `jekyll-sitemap` is on the allowlist).

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1** — `docs/_config.yml` contains a `plugins:` list including `jekyll-sitemap`, plus `url: https://chan4lk.github.io` and `baseurl: /specclaw`.
- **AC2** — `docs/robots.txt` exists, allows crawling (`User-agent: *` / `Allow: /`), and contains `Sitemap: https://chan4lk.github.io/specclaw/sitemap.xml`.
- **AC3** — `docs/llms.txt` exists and follows the convention: `# SpecClaw` H1, a one-line summary, and at least one `## ` section of markdown links.
- **AC4** — `docs/llms-full.txt` exists with expanded content covering: what it is, the propose→plan→build→verify→pr lifecycle, install commands, and the command list.
- **AC5** — `docs/index.md` title + description contain the target keywords; internal links resolve under `/specclaw`.
- **AC6** — `docs/INDEXING.md` exists listing owner-only steps and the drafted awesome-list submission text.
- **AC7** — No file under `plugins/specclaw/` is modified (NFR1). Version bumped in both manifests; CHANGELOG updated.

## Edge Cases

- **Relative vs absolute links** — with `baseurl: /specclaw`, in-site links must use `{{ site.baseurl }}` or absolute form so they don't 404 on the project-page path.
- **robots.txt processing** — Jekyll copies `robots.txt` verbatim if it has no front matter; keep it as a plain static file so `{{ }}` isn't required (hardcode the absolute sitemap URL).
- **llms.txt not a Jekyll page** — keep `.txt` files free of front matter so they're served raw, not rendered.

## Dependencies

- GitHub Pages build (Jekyll) — already configured via `docs/_config.yml`.
- `jekyll-sitemap` — GitHub Pages built-in allowlisted plugin (no Gemfile needed).

## Notes

Owner-only follow-ups (documented in AC6, not executed here): enable Pages, set repo homepage URL, Google Search Console verification + sitemap submit, upload custom social-preview image, and open the external awesome-list PRs.
