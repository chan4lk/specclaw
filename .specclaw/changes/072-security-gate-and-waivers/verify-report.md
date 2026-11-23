# Verification Report: 072-security-gate-and-waivers

**Verified:** 2026-11-20
**Model:** claude-opus-5-5
**Verdict:** PASS

Scope: `git diff ea1199a..HEAD` (12 commits, `e5e8a2b` … `af23c3f`). The repo has no `build.test_command`, so the
evidence below comes from the suites that cover this change. The four fast suites were re-run by this verifier at HEAD
`af23c3f`. The headless-PR result comes from the orchestrator's run after `05f257a`.

## Acceptance Criteria

- ✅ **AC-1:** With `presets: [node]`, the builder payload has `## Stack Security Rules` with base and node rules. An override replaces the built-in's rules. With no `## Security` sections, there is no heading. — `run-build-context-security-tests.sh` exit 0, 9 PASS, including "AC-1 no section without ## Security". Code: `specclaw-build-context` reads `specclaw-presets` output, extracts each `## Security` section with awk, skips empty ones, and only emits `SECURITY_SECTION` when `SECURITY_RULES` is non-empty. It is inserted after `${GUARDRAILS_SECTION}`.
- ✅ **AC-2:** The template has `security_review: true` and `security_review_block: false`. Plan, build and verify treat a missing key as on. — `templates/config.yaml`: `security_review: true  # … A missing key also means on.` / `security_review_block: false`. `run-infosec-reviewer-tests.sh` (25 PASS): "AC-2 workflow.security_review ships true" (the old "ships false" check was changed), "AC-2b … security_review_block ships false", AC-3/AC-7/AC-8 check that verify, plan and build now read "explicitly `false`" / "a missing key means on" / "unless `workflow.security_review` is `false`".
- ✅ **AC-3:** The gate exits 0/0/1/3 as specified. An empty-reason waiver and a waiver for another file waive nothing. — `run-security-gate-tests.sh` exit 0, 33 PASS: "no BLOCK exits 0", "every BLOCK waived exits 0", "one unwaived BLOCK exits 1", "missing report exits 3", "NOT_RUN exits 3", "empty-reason waiver: block stays (1)", "empty reason, unknown kind, short line each printed invalid", "same rule on another file waives nothing (1)". It also covers the Edge Cases: a heading outside `## Findings`, `|` inside the reason, a Windows drive-letter path, conflicting or empty verdicts, and usage errors (exit 2).
  - ⚠️ Edge case: the InfoSec re-review's one WARN (`specclaw-security-gate:23`, the BLOCK heading was case-sensitive and missed numbered headings) is **fixed**. `BLOCK_HEADING` (line 24) now has `re.I` and allows `\d+[.)]` prefixes. Tests "a lowercase [block] heading still blocks", "odd heading still blocks: [Block] … mixed case", "… 1. [BLOCK] … numbered" and "… 🔴 Block … emoji, bare word" pass (commits `7064e2e`, `af23c3f`).
- ✅ **AC-4:** `specclaw-pr` with block `true` and an unwaived BLOCK stops before staging and names the finding. With `false` it warns and continues. Valid waivers appear under `## Security waivers`. — `run-headless-pr-tests.sh` 61 passed, 0 failed (orchestrator run). Cases 072-4a…4j: exit 1, the message names `src/a.js` and `security-waivers.md`, and `gh pr create` is never called; block false exits 0 with `WARNING: security gate: unwaived BLOCK` and the PR is created; a waived BLOCK passes, and the body has `## Security waivers` with the reason. Code: `specclaw-pr` "Step 7-pre2" runs before "Step 7a: Stage and commit". It is skipped only when `security_review` is `"false"`, and a missing or non-executable gate gives `sec_rc=127`, a gate failure.
- ✅ **AC-5:** `infosec-reviewer.md` states the rule-field requirement, and verify 3.52 runs the gate. — `agents/infosec-reviewer.md:70`: "The rule field of every finding heading starts with the pack rule id or preset keyword it breaks (for example B13 or Access), so a waiver can name it." That sentence is in `ITEMS`, so the deleted-item mutant loop covers it. `verify.md` 3.52 step 4: "Run `specclaw-security-gate .specclaw <change>` and append … `**Security gate:**`". Check "072 AC-5 verify Step 3.52 runs specclaw-security-gate" passes.
- ✅ **AC-6:** B21–B24, DN10, DN11, PY12 and PY13 exist, B8 and B18 are extended, and the base, dotnet and python keywords exist. — `review-rules/base.md:54,56,58,60` (B21–B24, each with a severity: B24 "**major**"). `dotnet.md:14,16` (DN10, DN11). `python.md:18,19` (PY12, PY13). The B8 diff adds "outbound URLs". The B18 diff adds "a lookup that answers differently". `presets/base.md:31-33` adds Config, Identity and Redirects, and lines 20, 21 and 27 extend Injection, Access and Enumeration. `dotnet.md`/`python.md:34-35` add RateLimit and Proxy. The structural check is in `run-infosec-eval-cases-tests.sh` (see AC-7).
- ✅ **AC-7:** The 8 new eval cases pass `run-infosec-eval-cases-tests.sh`. — Exit 0, 22 PASS. The new cases are `fail-open-ownership` (B21|Access), `config-fallback` (B22|Config), `url-param-injection` (B8|Injection), `token-from-request` (B23|Identity), `open-redirect` (B24|Redirects), `resource-enumeration` (B18|Enumeration), `dotnet-forwarded-rate-limit` (DN11|Proxy, `.cs`) and `python-forwarded-rate-limit` (PY13|Proxy, `.py`). Each has `vulnerable.*`, `fixed.*` and `expect`.
  - ⚠️ No model was used to score the cases. That run is opt-in and costs API calls, and the AC only needs the structural check.
- ✅ **AC-8:** `run-infosec-evals.sh` chooses rules by sample extension, checked offline. — `rules_for()` maps `cs`→dotnet, `py`→python, `js|ts`→node and anything else to base only, and always includes base. `SPECCLAW_INFOSEC_RULES_FOR` prints the files and exits before the opt-in or model check. Checks "AC-8 a .cs / .py / .js sample gets … plus base", "AC-8 a .md sample gets base only" and "AC-8 every selected rule file exists" pass.
- ✅ **AC-9:** New suites are in `ci.yml`, existing suites still pass, and every version is equal and bumped. — `ci.yml` adds `run-build-context-security-tests.sh` and `run-security-gate-tests.sh`. Versions: 14 plugin manifests (`.claude-plugin` and `.codex-plugin`) plus 7 marketplace entries are all `0.9.19`, up from `0.9.17` at base and on `origin/main`, in one bump commit (`fcf83e3`). Existing suites: task-review 49/0, staged-files 55/0, headless-pr 61/0. `run-preset-check-tests.sh` (58) and specclaw-review `run-review-tests.sh` (10) fail on Windows, with the same counts and the same set with and without this change, so these failures are pre-existing and platform-specific, not regressions.
  - ⚠️ The version skips `0.9.18`. `tasks.md:79` reserves it for `specclaw/windows-test-portability` (change 071), so this is still a single patch bump past the next free number.

## Non-Functional Requirements

- **NFR-1 / NFR-2:** grep found 0 client identifiers and no copied pen-test-tool text (orchestrator check, not repeated here). The eval samples are short invented snippets.
- **NFR-3:** waiver matching and the PR block are in code (`specclaw-security-gate`, `specclaw-pr` Step 7-pre2), not in prose. The verify step is advisory and the block lives in `/specclaw:pr`.
- **NFR-4:** the gate is Python 3 stdlib only (`os, re, sys`). No GNU-only flags appear in the added lines (the tests use `sed -i.bak`, which is portable). `shellcheck` is not installed on this machine, so the "shellcheck clean" part is **unverified locally**. CI runs it.
- **NFR-5:** the production diff (tests and `.github` excluded, measured with `git diff --numstat ea1199a HEAD -- . ':!plugins/*/tests/*' ':!.github/*'`) is +255 / −33. That is under the 400-line cap. The largest file is `specclaw-security-gate` at 126 lines.

## Approach file map vs changed files

All 60 changed files fall inside the map: `bin/{specclaw-build-context,specclaw-security-gate,specclaw-pr}`, `templates/config.yaml`, `references/full/{plan,build,verify}.md`, `agents/infosec-reviewer.md`, `presets/{base,dotnet,python}.md`, `specclaw-review/review-rules/{base,dotnet,python}.md`, `tests/evals/infosec/*` (8 new cases), `tests/run-*.sh` (2 new, 4 updated), `.github/workflows/ci.yml`, and the manifests. Nothing falls outside the map.

## Test Results

```
run-security-gate-tests           exit 0   33 PASS   (re-run at af23c3f)
run-build-context-security-tests  exit 0    9 PASS   (re-run at af23c3f)
run-infosec-reviewer-tests        exit 0   25 PASS   (re-run at af23c3f)
run-infosec-eval-cases-tests      exit 0   22 PASS   (re-run at af23c3f)
run-task-review-tests             PASS: 49 FAIL: 0   (orchestrator)
run-staged-files-tests            PASS: 55 FAIL: 0   (orchestrator)
run-headless-pr-tests             61 passed, 0 failed (orchestrator, after 05f257a)
Known pre-existing Windows-only:  run-preset-check-tests 58 fail; specclaw-review run-review-tests 10 fail (identical without this change)
```

**InfoSec Review:** APPROVED_WITH_NOTES — 1 finding: 0 BLOCK, 1 WARN, 0 NOTE (that WARN is fixed in `af23c3f`, see AC-3)
**Security gate:** clear (`specclaw-security-gate .specclaw 072-security-gate-and-waivers` → exit 0)

## Issues Found

1. **The re-review is older than the WARN fix.** `security-report.md` still lists the BLOCK-heading WARN. The fix (`7064e2e`, `af23c3f`) is tested but has not been re-reviewed. **Fix:** optional. Add a one-line "resolved in af23c3f" note to the report or the PR body.
2. **Shellcheck was not run locally.** It is not on PATH here. **Fix:** rely on CI's shellcheck step, or run it before merge.

Neither issue blocks this change.

## Summary

**Passed:** 9/9 criteria
**Failed:** 0/9 criteria
**Verdict:** PASS

## After verify (review loop)

The verify agent checked `af23c3f`. The local review loop then ran 13 rounds and fixed every major found, in commits `f056ee0` through `6fbf724`. Main fixes:
- no ReDoS;
- loud failures from the preset resolver;
- verdict and path classes;
- a broken gate now counts as no answer in the evals;
- `--verdict` mode;
- empty rule tokens no longer match;
- one boolean reader for both security switches.

Final pass at `6fbf724`: clean (0 blocker, 0 major). Minors are in `follow-ups.md`.
`specclaw-review verdict` → `Review: CLEAN — 13 rounds, final pass 6fbf7248cb, models sonnet/opus`.
`run-headless-pr-tests` at `6fbf724`: 86 passed, 0 failed.
