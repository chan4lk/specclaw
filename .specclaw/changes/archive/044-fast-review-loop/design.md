# Design: specclaw-review

## Layout

```
plugins/specclaw-review/
  .claude-plugin/plugin.json   .codex-plugin/plugin.json
  .mcp.json                    # registers mcp/server.py (python3, stdio)
  hooks/hooks.json             # PreToolUse → hooks/guard-memory
  hooks/guard-memory           # python3, stdin JSON → deny/allow
  bin/specclaw-review          # python3 CLI over lib/
  lib/review_core.py           # config, rules, classify, diff/impact, prompt, backend, parse, calibrate, rounds, verdict, stats, learn, init
  lib/review_memory.py         # put / query / compact
  mcp/server.py                # JSON-RPC 2.0 stdio, tools → review_core / review_memory
  review-rules/{base,python,node,react-spa,nextjs,dotnet}.md
  templates/claude-rule.md     # written by `init` to .claude/rules/
  skills/review/SKILL.md       skills/learn/SKILL.md
  ci/azure-pipelines.yml       ci/github-actions.yml
  tests/run-review-tests.sh    tests/fixtures/…
```

## Key decisions

1. **Python, not Node, for the CLI and the MCP server.** The proposal said Node. Repo context says "`jq` and
   `python3` may be used in `bin/`", and the existing bins (`specclaw-preset-check`) are python3 with the stdlib
   only. One runtime means one core library shared by the CLI, the MCP server and the hook, and there is no
   Node dependency for Codex users.
2. **One core library; the CLI and the MCP server are thin.** This satisfies the "identical behaviour" claim and
   lets the tests drive the CLI only.
3. **Calibration is in code.** The spike shows severity inflation and duplicated passes. A prompt asking nicely
   is not a gate, so downgrades and dedupes happen after parsing (FR-5).
4. **There is no round cap.** Exit 4 (the repeat-fingerprint rule) is the only non-convergence guard, per
   operator decision.
5. **Verdict is derived, not stored.** It is recomputed from the round files and HEAD each time (context.md
   "Derived, not stored").
6. **Round files are the ledger.** They are written once per round and never edited: append-only, sum on read.
   `stats` reads them.
7. **Block-scoped YAML reader.** A tiny parser for the `review:` block only (scalars, inline lists, one nested
   map level). This repeats party's lesson: the whole-file `yaml_val` finds the wrong key.
8. **Backend is a command template run with `subprocess` (shell=False via `shlex.split`).** The prompt goes on
   stdin, avoiding argv limits (Project A's CI review script made the same choice). The default disables tools, settings
   and MCP so a review is one model turn.
9. **The guard matches path substrings** (`review-memory/` or the configured dir) inside tool_input values. For
   Bash it scans the command string. This is best-effort by design; the rules file and MCP-only writes are the
   backstop.

## Prompt contract (round)

```
<rulebook>  <memory slice ≤ budget>  <prior open findings (round>1): "is the fix a class fix? check variants">
<impact set: path:line: text>  <diff>
Return ONLY a JSON array: [{"severity":"blocker|major|minor","rule":"B1","file":"…","line":12,
"message":"…","scenario":"concrete input → wrong result (required for blocker/major)","in_delta":true}]
```

## File changes map

- New: everything under `plugins/specclaw-review/`.
- `plugins/specclaw/bin/specclaw-pr`: `review_line` under the Verdict, guarded.
- `plugins/specclaw-sync/bin/specclaw-azdo-pr`: the same line, placed outside the shrinkable bodies.
- `plugins/specclaw/skills/{verify,pr}/SKILL.md` and `plugins/specclaw/references/full/{verify,pr}.md`: a guarded
  optional step.
- `.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`, all manifests: version 0.8.2, plus the
  new entry.
- `tests/run-codex-plugin-tests.sh` (if it enumerates plugins), `.github/workflows/ci.yml`: register.
- `.specclaw/context.md`: architecture line for the fifth plugin.

## Risks

- Small-model misses → the final pass on a stronger model, and `stats` makes the miss rate visible.
- `claude -p` flags drift between CLI versions → the backend is configurable, and AC-18 smoke-tests the default.

## Grounding sources

- `.specclaw/context.md`: "Core never runs an add-on script without a `command -v` guard"; "All eight manifests
  and both marketplaces share one version"; "Every test suite must be registered in `.github/workflows/ci.yml`";
  "Append-only, sum-on-read ledgers".
- `findings.md` (spike): fix-induced late rounds, severity inflation, duplicate passes, base-merge noise.
