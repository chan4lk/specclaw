# Timeline: 067-fleet-push-retry

**Total measured (leaf spans):** 0s  ·  **Retries:** 0  ·  **Open spans:** 2 ⏱ still running

## By kind

- **phase** — 1m44s across 2 span(s)
- **wave** — 14m59s across 2 span(s)

## Slowest

- `W1` (wave) — wave 1 — **9m55s**
- `W2` (wave) — wave 2 — **5m04s**
- `plan` (phase) — plan — **1m23s**

## Spans

| Span | Kind | Label | Model | Attempt | Status | Duration |
|---|---|---|---|---|---|---|
| `propose` | phase | propose | - | - | ok | 21s |
| `plan` | phase | plan | - | - | ok | 1m23s |
| `W1` | wave | wave 1 | - | - | ok | 9m55s |
| `W2` | wave | wave 2 | - | - | ok | 5m04s ⚠ 7.0× median |
| `verify-1794773432` | phase | verify | - | - | - | ⏱ still running |
| `verify` | - | - | - | - | ok | ⏱ still running |
