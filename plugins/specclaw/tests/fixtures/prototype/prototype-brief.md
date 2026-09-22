# Prototype Brief: Dental Lab Rebuild

**Date generated:** 2026-09-18
**Plugin version:** 0.6.9
**Legacy commit:** 4f2a9c1d8e3b5a7c9f0d2e4b6a8c1d3e5f7a9b0c

**Frontend framework:** Kestrelize — sanctioned by `SQ-006` (`decisions.md`), decided by Dana Okafor, 2026-09-10
**Frontend language:** Runescript — sanctioned by `SQ-015` (`decisions.md`), decided by Priya Raman, 2026-09-12

_Build in this framework and this language only; do not choose either._

## What this prototype is for

The rebuilt work-order system reorganises how lab technicians move between a
customer, a case and its tooth chart. Before any of the application is built,
this throwaway prototype puts the redesigned screens in front of the lab
manager so the flow can be approved — or corrected — while changing it is still
cheap. It is design-acceptance code: the production team reads it as a
reference, and it is discarded afterwards.

## Inputs this brief was built from

| Document | sha256 |
|---|---|
| `.specclaw/ui/ui-inventory.md` | `e3b0c44298fc1c14…` |
| `.specclaw/analysis/domain-model.md` | `a1d0c6e83f027327…` |
| `.specclaw/analysis/functional-spec.md` | `9f86d081884c7d65…` |
| `.specclaw/analysis/module-map.md` | `2c624232cdd221771…` |
| `.specclaw/analysis/rebuild-backlog.md` | `b5bb9d8014a0f9b1…` |
| `.specclaw/analysis/decisions.md` | `7d865e959b2466918…` |
| `.specclaw/analysis/target-architecture.md` | `5f70bf18a086007016…` |

## Out of scope for the prototype

The prototype must not fake authentication, must not persist anything, and must
not stand in for real data. Static in-memory sample data is expected and must be
visibly labelled as sample data. No backend, no database, no authentication, no
network calls.

Sample data covers three customers and five work orders, enough to show the list
states the review points below refer to.

## Screens

### PS-001 — Work order list

- **Replaces:** `SCR-001` — Work order list
- **Module:** `MOD-002`
- **Serves:** `BL-014` (in scope)
- **Fields:**

| Field | Type | Required | Validation | Evidence |
|---|---|---|---|---|
| Order number | text (read-only) | yes | assigned on creation, never edited | `DR-021` — `domain-model.md` §Work Order |
| Customer | reference | yes | must be an active customer | `DR-022` — `domain-model.md` §Work Order |
| Due date | date | yes | not in the past at creation | `DR-021` — `domain-model.md` §Work Order |
| Status | enum | yes | one of Draft / In Lab / Shipped | `DR-023` — `domain-model.md` §Status |

- **Workflow steps:** open the list → filter by status or customer → open one
  order (`functional-spec.md` §Work Orders, "Finding an order").
- **Rules visible on this screen:** `DR-021` (the order number is shown on every
  row and never editable), `DR-023` (only the three listed statuses appear).
- **Tokens:** global `TK-COLOR`, `TK-TYPE` groups only.
- **Review points:**
  - Order number is visible on load — protects `DR-021`.
  - Only the three defined statuses appear in the filter — protects `DR-023`.
- **Proposed behaviour changes:** `PQ-007` — the redesign would drop the Draft
  status entirely and start orders at In Lab. That changes a status transition,
  so it is a question, not a design choice.

### PS-002 — Customer picker

- **Replaces:** `SCR-002` — Customer picker
- **Module:** `MOD-002`
- **Serves:** `BL-015` (in scope)
- **Fields:**

| Field | Type | Required | Validation | Evidence |
|---|---|---|---|---|
| Search | text | no | matches name or account code | `DR-030` — `domain-model.md` §Customer |
| Customer | list selection | yes | exactly one active customer | `DR-030` — `domain-model.md` §Customer |

- **Workflow steps:** search → select a customer → continue to the tooth chart
  (`functional-spec.md` §Work Orders, "Creating an order", steps 2–3).
- **Rules visible on this screen:** `DR-030` (inactive customers are not
  selectable).
- **Tokens:** global `TK-COLOR`, `TK-TYPE` groups only.
- **Review points:**
  - Customer is selected before the tooth chart is reachable — protects
    `workflow:WO-create:step2`.
  - Inactive customers cannot be selected — protects `DR-030`.
- **Proposed behaviour changes:** none.

### PS-003 — Case dashboard

- **Replaces:** NEW — sanctioned by `CQ-031`
- **Module:** `MOD-002`
- **Serves:** `BL-019` (in scope)
- **Fields:**

| Field | Type | Required | Validation | Evidence |
|---|---|---|---|---|
| Open cases | count (read-only) | yes | orders not yet Shipped | `DR-023` — `domain-model.md` §Status |
| Overdue cases | count (read-only) | yes | due date before today and not Shipped | `DR-021` — `domain-model.md` §Work Order |

- **Workflow steps:** open the dashboard → click a count → land on the list
  filtered to it (`CQ-031`'s decided answer).
- **Rules visible on this screen:** `DR-021`, `DR-023`.
- **Tokens:** global `TK-COLOR`, `TK-TYPE` groups only.
- **Review points:**
  - Overdue count excludes shipped orders — protects `DR-021`.
- **Proposed behaviour changes:** none. This screen exists only because `CQ-031`
  decided it should.

## Screens not carried forward

- `SCR-004` — Splash screen. Retired by `CQ-020` (decided): it carries no
  business rule and the redesign opens straight into the work-order list.

## Screens out of rebuild scope

- `SCR-003` — Reports. `BL-016` is scoped out to phase 2, so no prototype screen
  is required and it never blocks approval.

## Hand-off to the prototype skill

**Framework:** Kestrelize (`SQ-006`, Dana Okafor, 2026-09-10)
**Language:** Runescript (`SQ-015`, Priya Raman, 2026-09-12)

- Build in the stated framework and the stated language ONLY. Do not choose
  either, do not substitute either, and do not add a second language. If you
  cannot build in both as stated, stop and say so.
- Build only from the screen sections above. No invented screens, no invented
  fields, no invented rules.
- One route/screen per `PS-###`, with `data-testid="PS-###"` on each screen's
  root element.
- No backend, no database, no authentication, no network calls. Static in-memory
  sample data only, visibly labelled.
- This code is discarded after approval. Do not structure it as a production
  foundation and do not optimise it for reuse.

## Machine Directives

PS: PS-001 | SCR-001 | MOD-002 | BL-014 | DR-021,DR-022,DR-023
PS: PS-002 | SCR-002 | MOD-002 | BL-015 | DR-030
PS: PS-003 | NEW | MOD-002 | BL-019 | DR-021,DR-023
REVIEW-POINT: PS-001 | DR-021 | Order number is visible on load
REVIEW-POINT: PS-001 | DR-023 | Only the three defined statuses appear in the filter
REVIEW-POINT: PS-002 | workflow:WO-create:step2 | Customer is selected before the tooth chart is reachable
REVIEW-POINT: PS-002 | DR-030 | Inactive customers cannot be selected
REVIEW-POINT: PS-003 | DR-021 | Overdue count excludes shipped orders
PROVISIONAL: PS-001 | PQ-007
RETIRED-SCR: SCR-004 | CQ-020
LANG-FILE-CONVENTIONS: allow=.rs,.rsx forbid=.zz,.qq

---

_Generated by `/specclaw:bf-prototype`. Regenerated in full on every run — never hand-edit. Approvals are recorded by a named human in `prototype-approvals.md`, which no agent or script writes._
