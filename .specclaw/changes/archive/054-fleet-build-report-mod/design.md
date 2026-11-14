# Design: specclaw-fleet build report and mod

**Change:** 054-fleet-build-report-mod

## Approach

Three layers, each read-only toward the one beneath:

1. **Writers** add keys to the existing `specclaw-fleet run update:` comments. `specclaw-azdo-issue fields` already posts every `key=value` pair as a comment line, and `records` already parses any `- key: value` line, so specclaw-sync does not change.
2. **`specclaw-fleet report`** merges the records with best-effort AzDO and cluster reads into a snapshot document. That document is the one contract: `--json` prints it, `--save` stores it, `--html` embeds it, and the mod reads it.
3. **The mod** renders the snapshot only. It never shells out, so it is safe in any session and cheap on every redraw.

## File Map

| File | Change |
|---|---|
| `plugins/specclaw-fleet/image/run-stats.sh` | new: `agent_stats` prints the FR-1 pod `key=value` pairs |
| `plugins/specclaw-fleet/image/entrypoint.sh` | stamp `agent_started`, source `run-stats.sh` |
| `plugins/specclaw-fleet/image/draft-pr.sh` | `deliver` adds `$(agent_stats)` pairs to the final record |
| `plugins/specclaw-fleet/lib/launch.sh` | `pipeline_run=` on the dispatch record |
| `plugins/specclaw-fleet/lib/report.sh` | new: argument parsing, scope, run merge per change, gap fill |
| `plugins/specclaw-fleet/lib/report-render.sh` | new: totals, table, `--save`, `--html` |
| `plugins/specclaw-fleet/lib/report.html` | new: HTML template with a `__FLEET_REPORT__` placeholder and inline JS |
| `plugins/specclaw-fleet/bin/specclaw-fleet` | `report` route plus usage |
| `plugins/specclaw-fleet/hooks/mod.json`, `register.tsx`, `snapshot.ts` | new: mod wiring, the snapshot atom, and refresh |
| `plugins/specclaw-fleet/hooks/core/report.ts`, `view.ts` | new: pure parse, validate, timeline, and text |
| `plugins/specclaw-fleet/types/index.d.ts` | new: the `PluginState` contract |
| `plugins/specclaw-fleet/.claude-plugin/plugin.json` | `hooks` and `types` |
| `plugins/specclaw-fleet/tests/cases/ac34_run_stats.sh`, `ac35_report.sh` | new shell tests |
| `plugins/specclaw-fleet/tests/report.spec.ts`, `pane.test.ts`, `fixtures.ts`, `run-mod-tests.sh` | new mod tests |
| `plugins/specclaw-fleet/skills/report/SKILL.md`, `README.md` | the skill and docs |
| `.github/workflows/ci.yml` | run the fleet mod tests |

## Key Decisions

- **Wave is computed, not recorded.** The proposal listed `wave=` at dispatch. `feature_waves` already derives it from the graph, and a dispatch does not know its wave without that graph. So `report --feature` attaches the wave at read time. This avoids a second source of truth that can drift.
- **Cost is read from the last JSON object in `agent.log`.** It comes from `tail -c 65536 | jq -s 'last'` on a best-effort basis, and Claude's `--output-format json` prints a single result object. Codex prints text, so its cost keys are simply absent. It is labelled `API-equivalent estimate` because setup-token runs are not billed per token.
- **The snapshot gitignore is local to its folder.** `--save` writes `.specclaw/fleet/.gitignore` with `*`. The target repo's own `.gitignore` is never edited.
- **The timeline lives in the template's inline JS.** The shell embeds the snapshot JSON (escaped with `</` → `<\/`) in place of one placeholder. No HTML is built in bash.
- **Mod refresh is a regex on the Bash command,** `specclaw-fleet\s+(trigger|status|report)`, applied after `next(e)`. The read runs after the command has written the snapshot.
- **Times in the mod are UTC,** so the tests are deterministic and match AzDO and Kubernetes timestamps.

## Risks

- **Old records lack agent times.** The fallback to record `at` times keeps the timeline usable, only coarser.
- **AzDO rate limits or missing permissions on a large scope.** Reads are one call per change per API, and a failure only blanks fields.
- **The `entrypoint.sh` line budget (80).** New logic goes in `run-stats.sh`, and `entrypoint.sh` gains only two lines.

## Grounding Sources

- `CLAUDE.md`: "Always bump the plugin version before opening a PR", which applies to every plugin.
- `plugins/specclaw/hooks/*`: the mod structure is mirrored (`mod.json` → `register.tsx`, a pure `core/`, an atom with a `shape`).
- `plugins/specclaw-sync/bin/specclaw-azdo-issue`: "`fields` … always posts one comment listing every pair". New keys need no sync change.
