# Design: MCP Feedback Endpoint

## Architecture

Add a new composite MCP tool `feedback` following the exact same pattern as the existing 5 tools. No new tables, no schema changes, no new auth mechanism — the tool reuses `TokenContext.userId` (already scoped to the authed user by the bearer token layer).

## Tool Schema (flat z.object)

```ts
z.object({
  action: z.enum(["list_inbox", "get", "submit", "decline"]),
  responseId: z.string().optional(),   // required for get/submit/decline
  text: z.string().min(1).optional(),  // required for submit
})
```

No `discriminatedUnion` — Copilot Studio compatibility constraint.

## Action → Prisma mapping

| Action | Prisma operation |
|--------|-----------------|
| `list_inbox` | `findMany` where `{ respondentId: ctx.userId, status: "PENDING" }`, include feedbackRequest + employee |
| `get` | `findUnique` by `responseId`, verify `respondentId === ctx.userId` |
| `submit` | `update` where `{ id: responseId }`, set `status: "RESPONDED"`, `response: text`, `submittedAt: new Date()` |
| `decline` | `update` where `{ id: responseId }`, set `status: "DECLINED"` |

## Nested include shape (list_inbox + get)

```ts
{
  feedbackRequest: {
    include: {
      employee: { select: { id, name, email, image } },
    },
  },
}
```

## Error handling

All actions check `ctx.userId` first → `UNAUTHORIZED` if null.
`get`/`submit`/`decline` verify ownership → `FORBIDDEN`.
`submit`/`decline` check status is `PENDING` → `CONFLICT`.
Missing `responseId` or `text` → `VALIDATION` with `field`.

## File Map

| File | Change |
|------|--------|
| `src/app/api/mcp/tools/feedback.ts` | **Create** — full tool (schema, handlers, register export) |
| `src/app/api/mcp/tools/server.ts` | **Edit** — import + call `registerFeedbackTool(server, ctx)` |
| `e2e/admin.spec.ts` | **Edit** — no change needed (MCP tools don't have direct UI) |

## Pattern reference

Closest existing file to copy structure from: `src/app/api/mcp/tools/key_result.ts`
- Same guard pattern (`if (!ctx.userId) return err(...)`)
- Same `ok()` / `err()` / `toMcpContent()` usage
- Same `registerXxxTool(server, ctx)` export pattern
