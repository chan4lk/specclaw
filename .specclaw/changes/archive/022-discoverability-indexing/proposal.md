# Proposal: Discoverability & indexing (Google, GitHub, AI search)

**Created:** 2026-07-17
**Status:** 🟡 Draft

## Problem

SpecClaw has the repo hygiene now (topics, badges, `.github/`, hero README), but it's still nearly invisible to the three channels that drive organic stars:

- **Google / web** — a README alone barely ranks. There's no crawlable HTML site published, no sitemap, no `robots.txt`, and the repo has no homepage URL.
- **GitHub search** — helped by topics (done) but ranking compounds with backlinks and inbound listings we haven't created.
- **AI search** (ChatGPT / Perplexity / Claude / Gemini) — these cite from the web crawl and high-authority pages. There is no `llms.txt` (ironic, since SpecClaw itself reads `llms.txt`) and nothing steering LLMs to a clean, structured description.

Result: people who would use SpecClaw can't find it. Discoverability is the current ceiling on star growth.

## Proposed Solution

Ship the in-repo SEO/indexing scaffolding so the `docs/` GitHub Pages site is crawlable and AI-citable, then prepare external submissions.

1. **`jekyll-sitemap`** plugin in `docs/_config.yml` → auto-generated `sitemap.xml`.
2. **`docs/robots.txt`** allowing crawl and pointing to the sitemap.
3. **`docs/llms.txt`** — structured, keyword-clear project summary + key links for LLM retrieval.
4. **README/docs cross-links** and canonical description tuned for search intent ("spec-driven development for Claude Code", "Claude Code plugin", etc.).
5. **Prep external submissions** — draft PRs/entries for `awesome-claude-code` and Claude Code plugin directory lists (content prepared in-repo; actual submission is a follow-up).

## Scope

### In Scope
- `docs/_config.yml` sitemap plugin config
- `docs/robots.txt`
- `docs/llms.txt`
- Minor keyword tuning of `docs/index.md` front matter / description
- A short `docs/` note or checklist for the owner-only steps
- Draft text for awesome-list / directory submissions

### Out of Scope
- Enabling GitHub Pages (owner-only, Settings UI)
- Setting the repo homepage URL (owner-only)
- Google Search Console verification + sitemap submission (owner-only)
- Uploading the custom social-preview image (owner-only)
- Actually opening PRs against external `awesome-*` repos (follow-up, needs owner call)

## Impact

- **Files affected:** ~4–5 (estimated)
- **Complexity:** small
- **Risk:** low (docs-only; no plugin runtime code touched)

## Open Questions (resolved)

1. **Domain:** default GitHub Pages — `https://chan4lk.github.io/specclaw`. All sitemap/robots URLs use this base.
2. **llms.txt:** ship both — a short `llms.txt` index **and** a full `llms-full.txt` with expanded content.
3. **Awesome-lists:** maintainer's call — target `hesreallyhim/awesome-claude-code`, `awesome-claude` (Claude Code plugins section), and any Claude Code plugin-marketplace directory. Submission text prepared in-repo; opening the external PRs is a follow-up.

---

**To proceed:** Review this proposal and approve to begin planning.
