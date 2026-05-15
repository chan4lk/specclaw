---
layout: default
title: Privacy Policy — SpecClaw
---

# Privacy Policy

**Last updated:** 2026-05-15

## Summary

SpecClaw is an open-source Claude Code plugin that runs entirely in the user's local environment. **The plugin itself does not collect, store, transmit, or share any user data.** There is no telemetry, no analytics, no phone-home, no external server operated by the plugin author.

## What the plugin does locally

When you use SpecClaw, the following data is created and stored **only on your machine** (or wherever your local git repo lives):

- `.specclaw/` directory inside your project, containing proposals, specs, designs, task lists, status, errors, learnings, and verify reports.
- `.specclaw/.env` for credentials you provide (Azure DevOps PAT, Jira API token) — this file is gitignored and never committed.
- Logs printed to your terminal.

None of this is sent anywhere by the plugin.

## When the plugin makes network calls

SpecClaw makes outbound network calls **only when you explicitly invoke a lifecycle command that integrates with an external service you have configured**:

- **GitHub** — when you run `/specclaw:pr`, `/specclaw:propose` (with `github.sync: true`), or `/specclaw:archive`, the plugin uses the `gh` CLI (authenticated by you) or a `GITHUB_TOKEN` you supply to create/update issues and pull requests in your own repo.
- **Azure DevOps** — when you run `/specclaw:auth-azdo`, `/specclaw:pr-azdo`, the plugin calls the ADO REST API using a Personal Access Token you create and supply.
- **Jira** — when you run `/specclaw:auth-jira`, `/specclaw:issue`, the plugin calls the Atlassian REST API using credentials you create and supply.

In every case, the request goes **directly from your machine to the external service**. The plugin author does not operate a proxy or intermediary, does not see your credentials, and does not see your request payloads.

## Data you choose to send to these external services

What you send to GitHub, Azure DevOps, and Jira is governed by **those services' own privacy policies**:

- GitHub: https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement
- Azure DevOps: https://privacy.microsoft.com/en-us/privacystatement
- Atlassian / Jira: https://www.atlassian.com/legal/privacy-policy

SpecClaw transmits to those services only the content you'd otherwise type into them manually (proposal text, spec body, task list, PR title and description).

## Claude Code and the underlying model

Your conversation with Claude Code — including any text you type at the prompt and any output the model generates — is handled by Anthropic according to **Anthropic's privacy policy**: https://www.anthropic.com/legal/privacy

SpecClaw is a thin orchestration layer that runs alongside Claude Code; it has no separate data pipeline.

## Credentials

Personal Access Tokens and API tokens for Azure DevOps and Jira are stored locally in `.specclaw/.env` inside your project directory. This file is:

- Created with restrictive permissions (readable only by the user).
- Listed in `.gitignore` so it is not committed to your repository.
- Never transmitted by the plugin to any third party (other than the originating service, when you invoke that service's integration).

If you need to rotate or remove a credential, edit or delete `.specclaw/.env` directly.

## Children

SpecClaw is a developer tool and is not directed at children under 13.

## Contact

Issues, questions, or concerns: open an issue at https://github.com/chan4lk/specclaw/issues or contact the maintainer at chan4lk@gmail.com.

## Changes

This policy may be updated as the plugin evolves (for example, if new integrations are added). The current version is always available at this URL, with the `Last updated` field at the top reflecting the most recent change.
