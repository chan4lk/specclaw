# Proposal: MCP Feedback Endpoint for Claude Desktop

**Created:** 2026-05-09
**Status:** 🟡 Draft

## Problem

The feedback request flow in keyflow currently requires users to navigate the web UI to check pending feedback requests and submit responses. HR-initiated 360 feedback respondents must visit `/feedback/inbox`, open each request, and type a response in the browser form.

There is no way to interact with feedback requests from AI-powered tools like Claude Desktop. As teams use Claude Desktop for daily work, the context-switch to the browser creates friction and reduces response rates.

## Proposed Solution

Expose a **Model Context Protocol (MCP) server** alongside the keyflow Next.js app that provides tools for Claude Desktop (or any MCP client) to:

1. **List pending feedback requests** — retrieve the authenticated user's inbox of `FeedbackResponse` records with `PENDING` status, including the prompt and employee being reviewed
2. **Get feedback request detail** — fetch a single feedback request by ID with full context (prompt, employee info, due date, cycle label)
3. **Submit a feedback response** — post a text response to a specific `FeedbackResponse` record (marks it `RESPONDED`)
4. **Decline a feedback request** — decline a specific `FeedbackResponse` record (marks it `DECLINED`)

The MCP server will authenticate via the same session mechanism as the web app (bearer token or API key tied to a user account) and reuse existing Prisma queries/business logic.

## Scope

### In Scope
- New MCP server at `src/mcp/` (or standalone `mcp-server/`) using `@modelcontextprotocol/sdk`
- Four MCP tools: `list_feedback_inbox`, `get_feedback_request`, `submit_feedback_response`, `decline_feedback_response`
- Authentication via API key (stored in DB, scoped to a user) — simple bearer token approach
- Reuse of existing Prisma client and business logic from existing API routes
- Documentation / Claude Desktop config snippet in README

### Out of Scope
- OAuth / NextAuth session sharing with MCP (complex, deferred)
- MCP resources (streaming, subscriptions)
- Admin-side MCP tools (creating feedback requests)
- Peer feedback (`/api/feedback`) — only 360 HR-initiated feedback responses
- UI changes to the existing web app

## Impact

- **Files affected:** ~8–12 (estimated)
- **Complexity:** medium
- **Risk:** low — additive only, no changes to existing routes or schema

## Open Questions

1. **Auth approach:** Should API keys be stored in a new `ApiKey` table (scoped to user + tenant), or is a simpler shared secret per-tenant sufficient for MVP?
2. **Transport:** Stdio (local Claude Desktop) or HTTP SSE (remote)? Stdio is simpler for local use; HTTP SSE enables hosted scenarios.
3. **Server location:** Standalone process (`mcp-server/server.ts` run with `bun`) vs. Next.js API route adapter? Standalone is cleaner for MCP stdio.
4. **Schema change needed?** If we add an `ApiKey` model, a Prisma migration is required — is that acceptable scope?

---

**To proceed:** Review this proposal and approve to begin planning.
