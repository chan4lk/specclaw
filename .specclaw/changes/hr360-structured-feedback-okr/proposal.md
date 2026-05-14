# Proposal: HR 360 — Structured Feedback via MCP Prompts, Anonymized Views & OKR Conversion

**Created:** 2026-05-10
**Status:** 🟡 Draft

## Problem

The existing HR 360 feedback flow collects plain-text responses. This creates three gaps:

1. **No structure** — a plain-text paragraph cannot be broken into department-specific scored categories. Different departments (Engineering, Sales, HR, etc.) have different competency frameworks with different sub-items to score. HR cannot aggregate or compare scores across respondents.

2. **No anonymized view** — employees have no way to see their own feedback. HR has no consolidated view of all responses for a request. Respondent identity must be hidden from the employee.

3. **No OKR conversion** — there's no way to turn structured feedback into draft Objectives & Key Results. Employees must do this manually.

**Note:** Join date management is already fully implemented (API + HR Users UI). This proposal does not include it.

## Proposed Solution

### 1 — Feedback Templates + MCP Prompts

HR creates **FeedbackTemplate** records per department. Each template defines categories and sub-items to score. Examples:

**Engineering template:**
```
- Technical Skills: Code Quality (1-5), Problem Solving (1-5), System Design (1-5)
- Collaboration: Pair Programming (1-5), Code Reviews (1-5)
- Delivery: On-time completion (1-5), Estimation accuracy (1-5)
```

**Sales template:**
```
- Customer Engagement: Relationship building (1-5), Follow-up (1-5)
- Pipeline: Forecasting (1-5), Deal closure (1-5)
- Communication: Presentation skills (1-5), Written comms (1-5)
```

Templates are exposed as **MCP Prompts** via a new prompts capability on the MCP server. When Claude Desktop opens a feedback session, it loads the employee's department prompt — so Claude guides the respondent through the exact categories and sub-items relevant to that person, then formats and submits structured JSON.

A second MCP prompt (`feedback-to-okrs`) encodes the John Doerr OKR methodology instructions for converting feedback scores into draft OKRs.

### 2 — Structured Storage on FeedbackResponse

Add `structuredData Json?` to `FeedbackResponse`. When submitted via MCP, both `response` (plain-text summary) and `structuredData` are persisted:

```json
{
  "templateId": "<FeedbackTemplate.id>",
  "categories": [
    {
      "name": "Technical Skills",
      "items": [
        { "name": "Code Quality",    "score": 4 },
        { "name": "Problem Solving", "score": 5 },
        { "name": "System Design",   "score": 3 }
      ],
      "comment": "Strong reviewer, sometimes over-engineers."
    }
  ],
  "overallComment": "A reliable engineer who communicates well."
}
```

The MCP `feedback` tool's `submit` action gains an optional `structured` parameter.

### 3 — Anonymized Feedback Views

**HR view** (`/dashboard/admin/feedback-requests/[id]/results`):
- Full table: respondent name, per-category scores, sub-item breakdowns
- Aggregate averages per category and sub-item

**Employee view** (`/dashboard/feedback/results/[requestId]`):
- Aggregate scores only — no respondent identity
- Anonymized comments (stripped of identifying details — just the text)
- Unlocks only after ≥ 3 responses (default; not configurable in this iteration)

**API routes:**
- `GET /api/admin/feedback-requests/[id]/results` — HR: full de-anonymized results + structured data
- `GET /api/feedback-results/[requestId]` — Employee: anonymized aggregate only

### 4 — OKR Conversion via MCP (`to_okrs` action)

New action on the `feedback` MCP tool. Workflow:
1. Employee calls `feedback(action='to_okrs', requestId='...')` in Claude Desktop
2. MCP server returns the employee's aggregated structured feedback
3. Claude Desktop applies the `feedback-to-okrs` MCP prompt (John Doerr methodology)
4. Claude generates draft OKR text: *"I will [Objective] as measured by [Key Result]"*
5. Employee confirms, then calls `feedback(action='create_okrs', requestId='...', cycleId='...', objectives=[...])`
6. Server creates draft `Objective` + `KeyResult` records in Keyflow

`to_okrs` returns the aggregated data + guidance; `create_okrs` persists the confirmed OKRs. `cycleId` is always required — Claude prompts the user to pick from their active cycles (retrieved via the `cycle` MCP tool).

## Scope

### In Scope
- `FeedbackTemplate` Prisma model (id, tenantId, name, department, schema Json)
- `structuredData Json?` column on `FeedbackResponse` (migration)
- MCP Prompts capability: `list_prompts` + `get_prompt` handlers on MCP server
- Per-tenant template prompt registered dynamically from DB
- `feedback-to-okrs` system prompt resource (static, encodes Doerr methodology)
- MCP `feedback` tool: update `submit` (add `structured` param); add `to_okrs` + `create_okrs` actions
- API `GET /api/admin/feedback-requests/[id]/results` (HR results)
- API `GET /api/feedback-results/[requestId]` (employee anonymized results)
- API `GET/POST /api/admin/feedback-templates` (HR template management)
- UI: HR results page — respondent table + category/sub-item score grid
- UI: Employee results page — anonymized aggregate view
- UI: HR template management page (create/edit templates, assign to FeedbackRequest)

### Out of Scope
- Join date management (already done)
- Email notifications on submission
- PDF/export of results
- Historical trend views across cycles
- AI-generated summary of results (plain text digest)

## Impact

- **Files affected:** ~18 (estimated)
- **Complexity:** large
- **Risk:** medium — DB migrations + new MCP Prompts capability + 3 new UI pages

## Open Questions

1. ~~Min responses before employee view unlocks?~~ → **3** (fixed default for now)
2. ~~`to_okrs` cycle selection?~~ → **Prompt user** to pick from active cycles via MCP
3. ~~Fixed or customizable categories?~~ → **Customizable per department** via MCP Prompts backed by DB templates

---

**To proceed:** Review this proposal and approve to begin planning.
