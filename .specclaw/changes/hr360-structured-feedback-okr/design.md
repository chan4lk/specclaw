# Design: HR 360 — Structured Feedback via MCP Prompts, Anonymized Views & OKR Conversion

**Change:** hr360-structured-feedback-okr

## Architecture Overview

The feature adds four layers:
1. **DB layer** — new `FeedbackTemplate` model, two schema additions
2. **API layer** — template CRUD, HR results, employee results endpoints
3. **MCP layer** — update feedback tool (structured submit + to_okrs + create_okrs), add prompts capability
4. **UI layer** — template management, HR results view, employee results view

## Prisma Schema Changes

### New model — `FeedbackTemplate`

```prisma
model FeedbackTemplate {
  id         String   @id @default(cuid())
  tenantId   String
  name       String
  department String
  schema     Json
  // schema shape: Array<{
  //   name: string;
  //   items: Array<{ name: string }>;
  // }>
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt

  feedbackRequests FeedbackRequest[]

  @@index([tenantId])
  @@map("feedback_templates")
}
```

### Additions to `FeedbackRequest`

```prisma
  templateId String?
  template   FeedbackTemplate? @relation(fields: [templateId], references: [id], onDelete: SetNull)
```

### Addition to `FeedbackResponse`

```prisma
  structuredData Json?
```

## API Design

### Template endpoints (`/api/admin/feedback-templates`)

All require `manage:feedback-requests` RBAC permission. Standard server-side auth via `auth()`.

**GET** — returns `FeedbackTemplate[]` for `tenantId`. Ordered by `department, name`.

**POST** — body:
```ts
{
  name: string;           // required, min 1
  department: string;     // required, min 1
  schema: CategorySchema[]; // required, min 1 category
}
// CategorySchema: { name: string; items: { name: string }[] }
```

**GET `/[id]`** — returns single template; 404 if not found or wrong tenant.

**PATCH `/[id]`** — partial update of name, department, schema.

**DELETE `/[id]`** — returns 409 if any non-CLOSED `FeedbackRequest` references this template.

### HR results endpoint (`/api/admin/feedback-requests/[id]/results`)

Requires `manage:feedback-requests`. Returns:

```ts
{
  request: { id, prompt, dueAt, cycleLabel, template: { name, department, schema } | null };
  employee: { id, name, email, image };
  responses: Array<{
    respondentId: string;
    respondentName: string | null;
    respondentEmail: string | null;
    response: string | null;
    structuredData: StructuredPayload | null;
    submittedAt: string;
  }>;
  aggregates: {
    responseCount: number;
    structuredCount: number;
    categories: Array<{
      name: string;
      average: number;
      items: Array<{ name: string; average: number }>;
    }>;
  };
}
```

Aggregation logic:
- Only RESPONDED responses included in aggregates
- Per-item average: mean of `score` values across all structured responses that have the item
- Per-category average: mean of per-item averages

### Employee results endpoint (`GET /api/feedback-results/[requestId]`)

Returns 403 if caller is not the employee. Returns 423 (`{ error: "LOCKED", respondedCount: N }`) if RESPONDED count < 3.

```ts
{
  requestId: string;
  employeeId: string;
  respondedCount: number;
  aggregates: {
    categories: Array<{
      name: string;
      average: number;
      items: Array<{ name: string; average: number }>;
    }>;
  };
  comments: string[]; // plain-text response field from each RESPONDED response
}
```

## MCP Design

### MCP Prompts capability

`createMcpServer(ctx)` becomes `async`. Before returning the server:

```ts
// Load tenant templates
const templates = await prisma.feedbackTemplate.findMany({
  where: { tenantId: ctx.tenantId }
});

// Register one prompt per template
for (const tmpl of templates) {
  server.prompt(
    `feedback-template-${tmpl.id}`,
    `Department feedback guide: ${tmpl.name} (${tmpl.department})`,
    () => ({
      messages: [{
        role: "user" as const,
        content: { type: "text" as const, text: buildTemplatePromptText(tmpl) }
      }]
    })
  );
}

// Register static OKR conversion prompt
server.prompt(
  "feedback-to-okrs",
  "John Doerr OKR methodology instructions for converting 360 feedback into draft Objectives & Key Results",
  () => ({
    messages: [{
      role: "user" as const,
      content: { type: "text" as const, text: FEEDBACK_TO_OKRS_PROMPT }
    }]
  })
);
```

`buildTemplatePromptText(tmpl)` produces markdown like:
```
You are helping a colleague complete a 360 feedback survey for a {{department}} team member.

Guide them through each category below. For each sub-item, ask for a score from 1–5 (1=needs improvement, 5=exceptional) and an optional comment.

## Categories

### {{category.name}}
- {{item.name}}
- {{item.name}}

...

After collecting all scores and comments, call feedback(action='submit', responseId='...', text='<plain summary>', structured=<JSON>).
```

`FEEDBACK_TO_OKRS_PROMPT` (static string):
```
You are helping an employee convert their 360 feedback results into Objectives & Key Results using the John Doerr method.

The John Doerr OKR format is:
  "I will [Objective] as measured by [Key Result]."

Rules:
- Objectives: aspirational, qualitative, time-bound. Max 3–5 words.
- Key Results: specific, measurable, verifiable. 2–4 per objective.
- Focus on the lowest-scoring feedback categories (score < 3.5) as growth areas.
- Highest-scoring categories can anchor one "maintain" objective.

Given the aggregated feedback scores, draft 2–3 objectives with 2–3 key results each.
Then call feedback(action='create_okrs', requestId='...', cycleId='...', objectives=[...]) to save them.
```

### Route changes for async createMcpServer

`route.ts` currently calls `createMcpServer(tokenCtx)` synchronously within the request handler. Change to `await createMcpServer(tokenCtx)`. Route handler is already async.

### MCP feedback tool updates

**Updated FeedbackSchema:**
```ts
export const FeedbackSchema = z.object({
  action: z.enum([
    "list_inbox", "get", "submit", "decline", "to_okrs", "create_okrs"
  ]),
  responseId: z.string().optional(),
  text: z.string().min(1).optional(),
  structured: z.string().optional(), // JSON string, parsed server-side
  requestId: z.string().optional(),
  cycleId: z.string().optional(),
  objectives: z.array(z.object({
    title: z.string().min(1),
    description: z.string().optional(),
    keyResults: z.array(z.object({
      title: z.string().min(1),
      targetValue: z.number().optional(),
      unit: z.string().optional(),
    })).min(1),
  })).optional(),
});
```

**handleSubmit changes:**
- Parse `input.structured` as JSON if provided (catch parse errors → VALIDATION)
- Pass `structuredData` to prisma update

**handleToOkrs:**
- Auth check (UNAUTHORIZED)
- Fetch FeedbackRequest by requestId (NOT_FOUND)
- Ownership check (FORBIDDEN)
- Count structured RESPONDED responses (< 3 → CONFLICT)
- Aggregate scores and return

**handleCreateOkrs:**
- Auth check
- Validate cycleId
- Create objectives in transaction
- Return created records

## UI Design

### `/dashboard/admin/feedback-templates` — Template Management

Pattern: Server component (`page.tsx`) → Client component (`TemplatesClient.tsx`).

**List view:** Table with columns: Name, Department, Categories, Actions (Edit, Delete).

**Create/Edit modal:** 
- Name (text input), Department (text input)
- Category editor: add/remove categories, each with add/remove sub-items
- Sub-items are simple text labels (no scoring config needed — all 1–5)

**Delete:** Calls DELETE API. Shows error if active requests reference the template.

### `/dashboard/admin/feedback-requests/[id]/results` — HR Results

Pattern: Server component (`page.tsx`) → Client component (`HrResultsClient.tsx`).

**Layout:**
- Top: request metadata card (employee name, prompt, template name, due date, response stats)
- Aggregate row: per-category averages as colored progress bars (1–5 scale)
- Respondent table: rows per respondent, columns per category/sub-item, cells show score (0 if no structured data)
- Comments section: collapsible per-respondent comment blocks

### `/dashboard/feedback/results/[requestId]` — Employee Results

Pattern: Server component → Client component.

**Locked state:** Progress indicator "X of 3 responses received. Check back when more colleagues respond."

**Unlocked:**
- Radar/bar chart of category averages (Recharts)
- Per-category expandable section with sub-item averages
- Anonymized comments list (no names, just text)

### FeedbackRequest creation — add template selector

In `FeedbackAdminClient.tsx` create form, add a dropdown: "Feedback Template (optional)" populated from `GET /api/admin/feedback-templates`. Submits `templateId` with the POST body.

## File Map

### New files

| File | Purpose |
|------|---------|
| `src/app/api/admin/feedback-templates/route.ts` | GET list, POST create |
| `src/app/api/admin/feedback-templates/[id]/route.ts` | GET, PATCH, DELETE |
| `src/app/api/admin/feedback-requests/[id]/results/route.ts` | HR de-anonymized results |
| `src/app/api/feedback-results/[requestId]/route.ts` | Employee anonymized results |
| `src/app/api/mcp/prompts.ts` | registerFeedbackPrompts(), FEEDBACK_TO_OKRS_PROMPT, buildTemplatePromptText() |
| `src/app/dashboard/admin/feedback-templates/page.tsx` | Template list server component |
| `src/app/dashboard/admin/feedback-templates/TemplatesClient.tsx` | Template CRUD client component |
| `src/app/dashboard/admin/feedback-requests/[id]/results/page.tsx` | HR results server component |
| `src/app/dashboard/admin/feedback-requests/[id]/results/HrResultsClient.tsx` | HR results client component |
| `src/app/dashboard/feedback/results/[requestId]/page.tsx` | Employee results server component |
| `src/app/dashboard/feedback/results/[requestId]/EmployeeResultsClient.tsx` | Employee results client component |

### Modified files

| File | Change |
|------|--------|
| `prisma/schema.prisma` | Add FeedbackTemplate model, templateId on FeedbackRequest, structuredData on FeedbackResponse |
| `src/app/api/mcp/tools/feedback.ts` | Add structured param to submit; add to_okrs, create_okrs handlers |
| `src/app/api/mcp/tools/server.ts` | Make createMcpServer async; call registerFeedbackPrompts |
| `src/app/api/mcp/route.ts` | await createMcpServer() |
| `src/app/api/admin/feedback-requests/route.ts` | Add optional templateId to CreateFeedbackRequestSchema |
| `src/app/admin/feedback/FeedbackAdminClient.tsx` | Add template dropdown to create form |
