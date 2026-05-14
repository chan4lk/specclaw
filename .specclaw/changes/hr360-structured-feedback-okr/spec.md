# Spec: HR 360 — Structured Feedback via MCP Prompts, Anonymized Views & OKR Conversion

**Change:** hr360-structured-feedback-okr
**Status:** Planning

## Requirements

### FR-1 — FeedbackTemplate model
HR can create, update, and delete `FeedbackTemplate` records scoped to their tenant. Each template has `name`, `department` (string label), and `schema` (Json array of categories, each with a name and sub-items). Templates are referenced optionally from `FeedbackRequest`.

### FR-2 — Template management API
- `GET /api/admin/feedback-templates` — list templates for tenant (requires `manage:feedback-requests`)
- `POST /api/admin/feedback-templates` — create template
- `GET /api/admin/feedback-templates/[id]` — get single template
- `PATCH /api/admin/feedback-templates/[id]` — update template
- `DELETE /api/admin/feedback-templates/[id]` — delete template (only if no active FeedbackRequests reference it)

### FR-3 — FeedbackRequest gains optional templateId
`FeedbackRequest` gets an optional `templateId` FK to `FeedbackTemplate`. HR may assign a template when creating a request via `POST /api/admin/feedback-requests`. Existing create endpoint is extended with optional `templateId` field.

### FR-4 — structuredData on FeedbackResponse
`FeedbackResponse` gains `structuredData Json?`. Stored alongside `response` (plain text) when submitted via MCP with the `structured` parameter.

**Structured payload schema:**
```json
{
  "templateId": "<FeedbackTemplate.id>",
  "categories": [
    {
      "name": "Technical Skills",
      "items": [
        { "name": "Code Quality",    "score": 4 },
        { "name": "Problem Solving", "score": 5 }
      ],
      "comment": "Strong reviewer."
    }
  ],
  "overallComment": "A reliable engineer."
}
```

### FR-5 — MCP Prompts capability
The MCP server registers prompts at session creation time (per-tenant, loaded from DB):
- One prompt per `FeedbackTemplate`: named `feedback-template-{templateId}`, returns structured guidance instructing Claude how to walk the respondent through each category/sub-item.
- One static prompt `feedback-to-okrs`: encodes the John Doerr OKR methodology for converting aggregated feedback scores to draft objectives.

`createMcpServer()` becomes async to load templates from DB before registering prompts.

### FR-6 — MCP feedback tool: update submit action
`feedback(action='submit')` gains optional `structured` parameter (Json). When provided, it is validated as parseable JSON and stored in `structuredData`. The existing `text` parameter remains required (plain-text summary). Both are persisted atomically.

### FR-7 — MCP feedback tool: to_okrs action
`feedback(action='to_okrs', requestId)`:
- Requires `ctx.userId` (UNAUTHORIZED if null)
- Fetches `FeedbackRequest` by `requestId` (NOT_FOUND if missing)
- Verifies `employeeId === ctx.userId` (FORBIDDEN if not)
- Counts RESPONDED responses with non-null `structuredData`
- Returns CONFLICT if < 3 structured responses exist (message: "Fewer than 3 structured responses — results not yet available")
- Aggregates per-category and per-item average scores across all RESPONDED responses
- Returns aggregated data for Claude to draft OKRs using the `feedback-to-okrs` prompt

### FR-8 — MCP feedback tool: create_okrs action
`feedback(action='create_okrs', requestId, cycleId, objectives)`:
- Requires `ctx.userId` (UNAUTHORIZED if null)
- Validates `cycleId` belongs to `ctx.tenantId` (NOT_FOUND if missing)
- `objectives` is `Array<{ title: string, description?: string, keyResults: Array<{ title: string, targetValue?: number, unit?: string }> }>`
- Returns VALIDATION if `objectives` is empty or any `title` is blank
- Creates one `Objective` (status: DRAFT, level: INDIVIDUAL, owner: ctx.userId) + child `KeyResult` records per item, in a single transaction
- Returns created objectives with their key results

### FR-9 — HR results API
`GET /api/admin/feedback-requests/[id]/results`:
- Requires `manage:feedback-requests`
- Scopes by `tenantId`
- Returns all RESPONDED `FeedbackResponse` records with respondent name/email + `response` text + `structuredData`
- Computes per-category and per-item average scores across all structured responses
- Returns the `FeedbackRequest` metadata (prompt, dueAt, template) alongside results

### FR-10 — Employee results API
`GET /api/feedback-results/[requestId]`:
- Requires authenticated session (`auth()`)
- Returns 403 if `session.user.id !== feedbackRequest.employeeId`
- Returns 423 (Locked) if RESPONDED count < 3
- Returns aggregated per-category and per-item average scores (no respondent identifiers)
- Returns anonymized `response` texts as an array (no respondent names)

### FR-11 — HR results UI
`/dashboard/admin/feedback-requests/[id]/results`:
- Server component + Client component pattern
- Accessible to TENANT_ADMIN, SUPER_ADMIN, HR_VIEWER only
- Shows: request metadata (employee name, prompt, template, due date), per-respondent table (name, per-category scores), aggregate average row, anonymized comment list

### FR-12 — Employee results UI
`/dashboard/feedback/results/[requestId]`:
- Server component + Client component pattern
- Accessible only to the authenticated employee who is the subject
- If < 3 responses: shows locked state with response count progress
- Shows: aggregate category/sub-item score chart, anonymized comments list

### FR-13 — Template management UI
`/dashboard/admin/feedback-templates`:
- List templates (name, department, category count)
- Create template — name, department, JSON schema editor (categories + sub-items)
- Edit / delete templates
- Link from FeedbackRequest creation form: optional template dropdown

## Acceptance Criteria

| # | Criterion |
|---|-----------|
| AC-1 | HR can POST a `FeedbackTemplate` with a valid schema; it persists and is returned in GET list |
| AC-2 | `FeedbackRequest` can be created with optional `templateId`; it's returned in GET |
| AC-3 | MCP `feedback(action='submit', structured={...})` persists `structuredData` on the FeedbackResponse |
| AC-4 | MCP `list_prompts` returns one entry per tenant template + `feedback-to-okrs` |
| AC-5 | `get_prompt` for a template ID returns text describing each category and sub-item with scoring instructions |
| AC-6 | `get_prompt` for `feedback-to-okrs` returns John Doerr methodology instructions |
| AC-7 | `feedback(action='to_okrs', requestId)` returns aggregated category averages |
| AC-8 | `to_okrs` returns CONFLICT with < 3 structured responses |
| AC-9 | `to_okrs` returns FORBIDDEN if caller is not the subject employee |
| AC-10 | `feedback(action='create_okrs')` creates Objective + KeyResult records; returns them |
| AC-11 | `create_okrs` with invalid `cycleId` returns NOT_FOUND |
| AC-12 | `GET /api/admin/feedback-requests/[id]/results` returns full results with per-category averages |
| AC-13 | `GET /api/feedback-results/[requestId]` returns anonymized aggregate; 403 if not the employee |
| AC-14 | Employee results API returns 423 if < 3 RESPONDED responses |
| AC-15 | HR results UI renders per-respondent score grid with aggregate row |
| AC-16 | Employee results UI shows locked state when < 3 responses |
| AC-17 | Template management UI allows create/edit/delete |

## Edge Cases

- Template deleted after assignment to FeedbackRequest → request valid; `structuredData` already stored is the source of truth
- `to_okrs` called when all responses are plain-text (no `structuredData`) → CONFLICT: "No structured responses available"
- `structured` payload stores mismatched schema → accept and store; no server-side schema enforcement
- Empty `objectives` array in `create_okrs` → VALIDATION error: "objectives must not be empty"
- `feedback(action='submit')` with `structured` but no `text` → existing VALIDATION: text required
- Employee views results page for a request they're not the subject of → 403 redirect to dashboard
