# Proposal: feedback-ux-improvements

## Status
`draft`

## Problem Statement

Three gaps in the current HR 360 feedback system degrade reliability and UX:

1. **No overdue reminders** — Respondents get a notification when assigned but nothing if they go silent. FeedbackResponse records sit PENDING past `dueAt` with no nudge. HR has no automated follow-up mechanism.

2. **Template schema not enforced on submit** — `FeedbackRequest` has an optional `templateId` linking to a `FeedbackTemplate` with a structured question schema. The `PUT /api/feedback-responses/[id]` endpoint accepts any `structuredData` blob (or none) regardless of whether a template is attached. Structured scores used in the results aggregation (`/api/admin/feedback-requests/[id]/results`) can be missing or malformed.

3. **Feedback management in wrong nav context** — The HR 360 feedback management UI lives at `/admin/feedback/` (the old `src/app/admin/` route group, separate from the main dashboard). The main dashboard already has an `/dashboard/hr/` section for HR-specific views. `HR_VIEWER` already holds `manage:feedback-requests` permission. Moving the page into `/dashboard/hr/feedback/` gives HR users a consistent single-pane experience without jumping to a separate admin URL.

## Proposed Solution

### 1. Feedback Overdue Reminder Cron
Add `POST /api/cron/feedback-reminders` following the existing pattern (`checkin-reminders`). Runs daily (or on demand). Finds all `FeedbackResponse` records where:
- `status = PENDING`
- `feedbackRequest.dueAt` is within N days (configurable, default 3) or already past
- `feedbackRequest.status = OPEN`

Sends an in-app notification (and optionally email) to each respondent. Avoids duplicate sends by checking last notification timestamp or using a `reminderSentAt` field on `FeedbackResponse`.

### 2. Template Schema Validation on Submit
In `PUT /api/feedback-responses/[id]`:
- If `feedbackRequest.templateId` is set, load the template's `schema` field
- Validate that `structuredData` in the request body satisfies the schema (required question IDs present, rating values in range)
- Return `400` with field-level errors if invalid
- Allow submit without `structuredData` only if no template is attached

### 3. Move Feedback Management to HR Dashboard
- Create `src/app/dashboard/hr/feedback/` with server page + client component (migrate from `src/app/admin/feedback/`)
- Gate with `can(role, "manage:feedback-requests")` (same as today)
- Update nav link in HR dashboard layout/sidebar to point to new route
- Remove `src/app/admin/feedback/` (or redirect to new route)
- Move `src/app/dashboard/admin/feedback-requests/` and `src/app/dashboard/admin/feedback-templates/` under `src/app/dashboard/hr/` for consistency

## Scope

**In scope:**
- New cron route + lib helper for feedback reminders
- Schema validation in the feedback-response PUT endpoint
- Page move + nav update for feedback management UI

**Out of scope:**
- Email reminders (in-app notification only for v1)
- Employee-facing visibility into who has/hasn't responded
- Auto-creation of FeedbackRequest from anniversary trigger
- Changes to `FeedbackTemplate` schema format

## Impact

- **HR admins / HR_VIEWERs:** Single consistent nav for all HR tools; no more context switch to `/admin/`
- **Respondents:** Overdue nudges reduce HR admin burden for manual follow-ups
- **Data quality:** Structured scores in results view are always complete when template is used

## Files Affected

```
src/app/api/cron/feedback-reminders/route.ts          (new)
src/lib/feedback-reminders.ts                          (new)
prisma/schema.prisma                                   (add reminderSentAt to FeedbackResponse)
prisma/migrations/                                     (migration for new field)
src/app/api/feedback-responses/[id]/route.ts           (add template validation, hard reject on schema mismatch)
src/app/api/feedback-responses/inbox/route.ts          (include structuredData in response payload)
src/app/dashboard/hr/feedback/page.tsx                 (new — replaces /admin/feedback/)
src/app/dashboard/hr/feedback/FeedbackHrClient.tsx     (new — migrated from FeedbackAdminClient)
src/app/dashboard/hr/feedback-requests/               (moved from /dashboard/admin/feedback-requests/)
src/app/dashboard/hr/feedback-templates/              (moved from /dashboard/admin/feedback-templates/)
src/app/admin/feedback/page.tsx                        (redirect or remove)
src/app/dashboard/hr/layout.tsx or nav component       (add Feedback link)
```

## Decisions

1. **Reminder cadence:** 3-days-before `dueAt` trigger (one send). Cron runs daily, finds responses where `dueAt` is exactly 3 days away and `reminderSentAt` is null.
2. **`reminderSentAt`:** Single timestamp — one reminder per response.
3. **Template validation:** Hard reject — `400` if `structuredData` missing or invalid when template attached.
4. **Nav consolidation:** Fully move to `/dashboard/hr/`. Also: feedback response list endpoints must include `structuredData` JSON in the response payload (currently omitted).
5. **SUPER_ADMIN access:** Inherits via `manage:feedback-requests` permission — no separate admin route needed.

## Estimated Effort

| Item | Estimate |
|---|---|
| Cron + reminder lib | medium |
| Schema validation | small |
| Page move + nav | small |
| Migration | small |

**Total:** ~1 day engineering
