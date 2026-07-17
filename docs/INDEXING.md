---
layout: default
title: Indexing & discoverability checklist — SpecClaw
---

# Indexing & discoverability

What's automated in the repo and what still needs a maintainer with repo-admin
or account access. Base site URL: `https://chan4lk.github.io/specclaw`.

## Shipped in-repo (done)

- `docs/_config.yml` — `jekyll-sitemap` plugin + `url`/`baseurl` → `sitemap.xml` at build.
- `docs/robots.txt` — allow-all + sitemap reference.
- `docs/llms.txt` — short llms.txt-convention index for AI search.
- `docs/llms-full.txt` — expanded, self-contained text for LLM ingestion.
- `docs/index.md` — keyword-tuned title and description.
- Repo topics (set via GitHub API): `claude-code`, `claude`, `anthropic`,
  `ai-agents`, `spec-driven-development`, `llm`, `claude-code-plugin`,
  `developer-tools`, `agentic-workflow`, `code-generation`.

## Owner-only steps (do these in the GitHub UI / external accounts)

1. **Enable GitHub Pages** — Settings → Pages → Source: `Deploy from a branch`,
   branch `main`, folder `/docs`. Wait for the first build.
2. **Set the repo homepage URL** — repo landing page, top-right ⚙ → Website:
   `https://chan4lk.github.io/specclaw`.
3. **Verify the sitemap** — after Pages builds, confirm
   `https://chan4lk.github.io/specclaw/sitemap.xml` returns XML.
4. **Google Search Console** — https://search.google.com/search-console →
   add the property → verify → submit `sitemap.xml`. (Bing Webmaster Tools
   optional, same flow.)
5. **Custom social-preview image** — Settings → General → Social preview →
   upload a 1280×640 card (reuse the hero, `docs/assets/specclaw-hero.png`).
6. **Custom domain (optional)** — if you add one, update `url`/`baseurl` in
   `_config.yml`, the `Sitemap:` line in `robots.txt`, and the URLs in
   `llms.txt` / `llms-full.txt`.

## External listings (drafted — open the PRs when ready)

Getting listed on curated lists is the biggest GitHub/Google backlink lever.
Suggested targets and ready-to-paste entry:

**Targets**
- `hesreallyhim/awesome-claude-code`
- `awesome-claude` (Claude Code plugins section, if present)
- Any Claude Code plugin-marketplace / directory repo

**Entry text**

```markdown
- [SpecClaw](https://github.com/chan4lk/specclaw) — Spec-driven development
  for Claude Code. Turns a plain-English idea into merged code through an
  automated propose → plan → build → verify → pr lifecycle, with structured
  proposals, specs, designs, and ordered task lists committed to your repo.
```

**Also worth doing (backlinks compound ranking):** a short "Show HN" / Reddit
r/ClaudeAI post, a dev.to write-up, and a 30-second demo GIF/video linked from
the README.
