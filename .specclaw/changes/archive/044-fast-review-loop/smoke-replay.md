# Replays: the local loop vs a real server-side PR review (AC-18, AC-23)

**Date:** 2026-10-16.

**Subject:** "Project A", a specclaw project whose PRs are reviewed in CI by a two-pass Opus review: pass A is
standards, pass B is design. That review runs with Read/Grep/Glob tools and the project's governance inlined.
Five of its merged PRs were replayed: **PR-A** to **PR-E**.

**Method:**
- Each replay ran on a throwaway `--shared` clone at the PR's first-iteration head and merge base.
- Nothing was pushed, and nothing was posted to the PR host.
- The PR host's API was read-only: iterations, threads, and pipeline status posts.

**Models:** `opus` = `claude-opus-5-5`, `sonnet` = `claude-sonnet-5-5`, `haiku` = `claude-haiku-5-5` (Claude Code
2.1.301 alias resolution).

## 1. Time

| PR | Server: pushes / review rounds | Server review per round (push → findings) | Server CI per push | Server CI minutes, whole PR | Local round, Opus |
|---|---|---|---|---|---|
| PR-A | 5 rounds | — | ~18 min | — | 120 s |
| PR-B (74 files) | 7 / 4 | 2–10 min | 13–19 min | 93 | 148 s |
| PR-C | 7 / 2 | 3 min | 3–22 min | 82 | 159–191 s |
| PR-D (frontend) | 6 / 4 | 2–7 min | 12–30 min | 95 | 86–118 s |
| PR-E (frontend) | 7 / 2 | 1–2 min | 6–18 min | 58 | 62–116 s |

- **Per round:** a local round takes 1–3 min. The server's review step is also fast, 1–10 min, so the wait per
  round barely changes.
- **Per PR:** rounds no longer push, so a PR pays for **one** CI run instead of 6–7. That saves **~40–80 build
  minutes per PR**.
- **Fix time:** the fix time between rounds (6–80 min) is untouched. Fewer rounds, through earlier detection and
  class fixes, is the lever for that.
- **Outliers:** two local runs took 12 and 37 min, while six or more Opus sessions ran at once. This is most
  likely throttling.

## 2. Configuration gaps found and closed

| Gap vs the server review | Effect | Fix |
|---|---|---|
| One pass, no tools, only part of the governance, docs skipped | First replay of PR-A: 3 of 5 round-1 issues | T8: `passes`, `tools`, `governance` (read live), docs in the diff |
| Haiku/Sonnet rounds against an Opus-reviewed project | Sonnet ≈ ⅓ of round-1 majors at major severity | Defaults are `round: sonnet` / `final: opus`; docs recommend Opus rounds for Opus-reviewed repos |
| Plugin severity rule ("major needs a scenario; records never major") vs a project rule ("anything touching project law is at least major") | Majors filed as minors: about half the server's count | `severity: project`, the default when `governance` is set |
| Two passes filing one issue on lines far apart | Inflated counts | Cross-pass dedupe on a shared backticked symbol |

## 2b. PR-A in match-Project-A mode (AC-23)

PR-A was replayed at its first-iteration head with the server review's configuration:
- Opus;
- `passes: [review, design]`;
- `Read,Grep,Glob` with 12 turns;
- the 11 governance files the server inlines, read live (a 2,737-line rulebook);
- docs in the diff.

Cheaper modes ran beside it on separate clones. One round each, compared with the server's 5 distinct round-1
major issues (8 threads):

| Server round-1 issue | Opus (120 s) | Sonnet (132 s) | Haiku (151 s) |
|---|---|---|---|
| 1. A stored answer hidden by a later "unavailable" row | ✅ major | ✅ major | ✅ major |
| 2. A house/plot number read as the postcode | ✅ major | ✅ major | ✅ major |
| 3. The documented service URL fails the prod URL rule (code, chart values and README disagree) | ◐ minor | ✅ major | — |
| 4. The data the external source served is not pinned | ✅ major | ✅ major | ✅ major |
| 5. Redirects are not refused | — | — | — |
| Server **round-3** issue: an input with nothing to ask is still searched and stored as "not found" | ✅ round 1 | ✅ round 1 | ✅ round 1 |
| Round totals (b/M/m) | 0/5/7 | 0/6/4 | 1/6/10 |

- **Result:** in match mode, one local round re-finds 4 of the server's 5 round-1 issues: Sonnet at major
  severity, Opus with one rated minor.
- **Earlier:** all three models raise, in round 1, an issue the server only reached in round 3.
- **Missed by all:** issue 5. That is the kind of gap the final pass and later rounds are there to sample.
- **Cleanup:** Opus's two passes filed issue 1 twice, on lines far apart. That led to the cross-pass symbol dedupe.

## 3. Severity experiment: three setups, round 1, PR-C / PR-D / PR-E

- **X:** the server's exact prompt, flags and governance, run locally, twice.
- **P:** the plugin with its own severity rules.
- **Q:** the plugin with `severity: project`, twice.

| PR | Server (b/M/m) | X run 1 · run 2 | P | Q run 1 · run 2 |
|---|---|---|---|---|
| PR-C | 0/4/10 | 0/5/8 · 0/6/8 | 0/2/4 | 0/4/4 · 0/4/4 |
| PR-D | 0/4/11 | 0/2/9 · 0/3/10 | 0/1/6 | 0/2/6 · 0/3/4 |
| PR-E | 0/3/9 | 0/4/8 · 0/3/6 | 0/2/7 | 0/3/3 · 0/3/1 |

**Same issues?** The server's 9 distinct round-1 majors on these three PRs:

| | X run 1 | X run 2 | Q run 1 | Q run 2 |
|---|---|---|---|---|
| Server majors re-found | 5/9 | 6/9 | 5/9 | 4.5/9 |

## 4. Why a local round cannot "match the server's count"

1. **A server round is one sample.** The server's own prompt, rerun on the same commit, re-finds only ~60% of
   that round's majors and finds others instead. No reviewer, local or server, reproduces a specific
   historical round.
2. **With `severity: project`, the plugin performs like the server prompt run locally** (Q ≈ X), both in counts
   and in issue overlap. The remaining difference from the historical server round is sampling variance, not
   the plugin.
3. **The loop covers variance.** Every later round, the class-fix rule and the Opus final pass each draw another
   sample. Local rounds also filed majors that the server only reached in a later round, or rated minor.

## 5. Earlier smoke run (AC-18)

PR-A was replayed before T8, with one pass, imported rules and no tools: Haiku 115 s and Sonnet 69 s. It
exercised every code path on a real repository: the rulebook, import, impact set, round records, memory,
verdict and stats.
