# Spec: MCP Feedback Endpoint

**Change:** mcp-feedback-endpoint
**Status:** Planning

## Requirements

### FR-1 — List pending inbox
The `feedback` tool with `action: "list_inbox"` MUST return all `FeedbackResponse` records where `respondentId` equals `ctx.userId` and `status = PENDING`, including nested `feedbackRequest` (with `prompt`, `dueDate`, `cycleLabel`) and `employee` (id, name, email, image).

### FR-2 — Get single response
The `feedback` tool with `action: "get"` and `responseId` MUST return the full `FeedbackResponse` record with the same nested includes as FR-1. MUST return `FORBIDDEN` if `respondentId !== ctx.userId`.

### FR-3 — Submit response
The `feedback` tool with `action: "submit"`, `responseId`, and `text` MUST:
- Verify `respondentId === ctx.userId` (else `FORBIDDEN`)
- Verify status is `PENDING` (else `CONFLICT`)
- Update status → `RESPONDED`, set `response = text`, set `submittedAt = now()`
- Return the updated record

### FR-4 — Decline response
The `feedback` tool with `action: "decline"` and `responseId` MUST:
- Verify `respondentId === ctx.userId` (else `FORBIDDEN`)
- Verify status is `PENDING` (else `CONFLICT`)
- Update status → `DECLINED`
- Return the updated record

### FR-5 — Unauthenticated rejection
When `ctx.userId` is null (machine token), all actions MUST return `UNAUTHORIZED`.

### FR-6 — Registration
The tool MUST be registered in `createMcpServer()` alongside the existing 5 tools.

## Acceptance Criteria

| # | Criterion |
|---|-----------|
| AC-1 | `list_inbox` returns only PENDING responses belonging to the authed user |
| AC-2 | `list_inbox` includes employee name and feedbackRequest prompt |
| AC-3 | `get` with a valid owned responseId returns full detail |
| AC-4 | `get` with another user's responseId returns `FORBIDDEN` error envelope |
| AC-5 | `submit` with valid text updates status to `RESPONDED` and sets `submittedAt` |
| AC-6 | `submit` on an already-RESPONDED record returns `CONFLICT` |
| AC-7 | `decline` updates status to `DECLINED` |
| AC-8 | `decline` on a RESPONDED record returns `CONFLICT` |
| AC-9 | Machine token (userId null) returns `UNAUTHORIZED` on any action |
| AC-10 | Schema uses flat `z.object` with `action` enum (no discriminatedUnion) |
| AC-11 | Tool registered in `server.ts` and appears in MCP tool list |

## Edge Cases

- `responseId` not found → `NOT_FOUND`
- Missing required param (`responseId`, `text`) → `VALIDATION` with `field` set
- `text` empty string on submit → `VALIDATION`
