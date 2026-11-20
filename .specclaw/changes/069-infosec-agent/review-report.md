# Code Review Report: 069-infosec-agent

**Reviewed:** 2026-11-17
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

10 findings: 0 BLOCK, 5 WARN, 5 NOTE

Scope: T6 to T9 only (commits 54ab625..HEAD). T1 to T5 were reviewed before, and I did not repeat them. D8 skipped: design.md absent, so there is no design to check against. D9: every touched file appears in a `Files:` list in tasks.md, and `tests/results/` is the only generated path. Both test suites pass locally (`run-infosec-reviewer-tests.sh`, `run-infosec-eval-cases-tests.sh`).

## Findings

### [WARN] plugins/specclaw/tests/run-infosec-evals.sh:65,81,83 — Correctness
**Problem:** The runner can finish green having measured nothing. Failed calls are swallowed (`$RULES" --model "$MODEL" --max-turns 1 2>/dev/null || true`) and the script never exits non-zero because of them. If auth fails or the CLI errors, every call is empty. The run then prints catch 0% and false-alarm 0%, lists "no answer" in the table and exits 0, so the nightly job passes. The header comment says an empty call "counts as a miss (never as clear)", but line 83 does not do that for `fixed`: `if [ -z "$r" ]; then c_none=$((c_none + 1)); elif grep -qE '^### \[BLOCK\]' ...`. An empty answer stays in the `fixed_total` denominator and lowers the false-alarm rate, so it is counted as clear. This is the "green eval that measured nothing" failure that line 41 of the same file says the suite guards against.
**Fix:** After the loop, add `[ "$answered" -gt 0 ] || { echo "FATAL: every call returned nothing." >&2; exit 2; }`. Better, fail when `no answer` exceeds some share of the calls. Drop empty `fixed` answers from `fixed_total`, or fix the comment.

### [WARN] plugins/specclaw/tests/run-infosec-evals.sh:81 — Correctness
**Problem:** The catch test is `grep -qiE "$pattern" <<<"$r"`. It runs case-insensitively over the whole report, Verdict Rationale included, and the pattern includes the plain keyword. For `B19|Codes`, `B17|Sessions`, `B8|Secrets`, `B20|Urls` and `ND11|Proxy`, ordinary words like "codes", "sessions" and "secrets" appear in almost any report on those samples, including a rationale that says "no issue with session handling". The catch rate is inflated, and a finding for a different rule, such as B16 on the otp case, also scores as a catch because both cases use the keyword `Codes`. FR-13 asks for "any finding that cites the expected rule id or keyword". The implementation does not restrict the match to findings.
**Fix:** Match only finding headings: `grep -E '^### \[(BLOCK|WARN|NOTE)\].*\b('"$want"')\b'`. Keep the rule id as the primary key and treat the keyword as a fallback. The stub test should also have a vulnerable-sample miss case, because today it only exercises the 100% path.

### [WARN] plugins/specclaw/references/full/build.md:164 — Design adherence (spec)
**Problem:** Step 2c does not do what FR-10 says. FR-10 says "A BLOCK goes down the task's normal retry path; when retries are used up it is written to `follow-ups.md`". Step 2c says "On `CHANGES_REQUESTED`, send the findings back to the task's agent once; if it is still `CHANGES_REQUESTED`, append the findings to `follow-ups.md` ... It is advisory: it never marks a task failed." That is a separate one-shot loop, not the normal retry budget. It also leaves the mechanics undefined: whether the task is re-committed, whether the security review runs again, and what "still" is compared against. FR-10 and AC-8 ("advisory") contradict each other, and neither the test nor the spec says which one wins.
**Fix:** Pick one behaviour and state it in the spec. For a one-liner: `On CHANGES_REQUESTED, append the findings to follow-ups.md and continue.` This is advisory, adds no loop and matches AC-8.

### [WARN] plugins/specclaw/tests/run-infosec-reviewer-tests.sh:31,35 — Test quality
**Problem:** Two of the new checks pass without the content they claim to guard.
- AC-8 ends with `grep -q "security-requirements.md" "$PLUGIN_DIR/references/full/build.md"`. That greps the whole file, and step 2c itself contains the string, so deleting the line that tells builders to read the requirements (build.md:75) still passes. AC-8 has "builders read `security-requirements.md`" as half of its condition.
- AC-6 greps "security-requirements.md", "security-report.md" and "SR-1" anywhere in the agent. Those strings already appear in Inputs and Output, so removing what each mode writes from the Modes section would not fail it. Only the `**Mode ...:**` labels are covered by mutants.
**Fix:** Scope the AC-8 clause to the payload line, for example `grep -q "add it to the payload" build.md`. Scope AC-6 to the Modes section: `sed -n '/^# Modes/,/^# Evidence/p'`.

### [WARN] plugins/specclaw/tests/evals/infosec/url-allowlist/fixed.js:6 — Test quality
**Problem:** The `fixed` samples are meant to draw no BLOCK, but two of them have defects a strict reviewer will report on their own, which contaminates the false-alarm rate.
- `url-allowlist/fixed.js:6`: `const upstream = await fetch(target);`. `fetch` follows redirects by default, so an allow-listed host that redirects reaches an internal address. That is the SSRF the allowlist is meant to prevent.
- `code-in-response/fixed.js:4`: `await codes.save(user.id, code, { ttlSeconds: 300 });`. `user` is not checked, so an unknown email throws, and the 500-versus-204 difference is account enumeration (B18). This sits next to the code leak the case is about.
Neither is in the vulnerable sample's intended flaw, so a BLOCK here is not a model failure.
**Fix:** Add `{ redirect: 'error' }` to the fetch. Add `if (!user) return res.status(204).end();` before the `codes.save`, in both samples so the pair differs only by the leak.

### [NOTE] plugins/specclaw/references/full/plan.md:27 — Design adherence
**Problem:** Step 3c says to skip when "the change is a spike", but size is first read in Step 4 (`specclaw-validate-change ... status`), one step later. The skip depends on information 3c has not fetched. Separately, 3c says to put each `SR-n` into `spec.md`, while 4a says "If `spec.md` already exists ... do not overwrite it". On the pre-authored-spec path the `SR-n` criteria would be silently dropped.
**Suggestion:** Read the size in 3c in one clause, and say "append the SR-n criteria to an existing spec.md" for that case.

### [NOTE] plugins/specclaw/tests/evals/infosec/session-after-logout/vulnerable.js:1 — Naming
**Problem:** The case is named `session-after-logout` but the sample is a password change (`router.post('/account/password', ...)`) that leaves other sessions alive. FR-12 lists "session surviving logout". The B17 rule covers both, but the name and the sample disagree.
**Suggestion:** Rename it to `session-after-password-change`, or make the sample a `/logout` handler.

### [NOTE] .github/workflows/infosec-evals.yml:25 — Complexity
**Problem:** The job has no `timeout-minutes`. A default run is 8 cases x 3 reps x 2 samples = 48 sequential model calls, and one hung `claude` call can hold the runner for the 6-hour default.
**Suggestion:** Add `timeout-minutes: 45` under `infosec:`.

### [NOTE] plugins/specclaw/tests/run-infosec-eval-cases-tests.sh:55 — Correctness
**Problem:** `rm -f "$PLUGIN_DIR"/tests/results/infosec-*.md` deletes every real result file in that directory, including a developer's earlier real eval run, not only the stub run's output. `tests/results/` is also not git-ignored, so real runs leave untracked files.
**Suggestion:** Run the stub with its own results directory and delete only that. This needs a `SPECCLAW_INFOSEC_RESULTS` override in the runner, and that override is the only addition. Or `rm -f` only the file the stub run printed on its `Result:` line.

### [NOTE] plugins/specclaw/agents/infosec-reviewer.md:62 — Correctness
**Problem:** "An unmet `SR-n` is a finding: BLOCK when the rule it comes from is a blocker, else WARN." The review-pack rules say "major" and "blocker", but the preset `## Security` bullets (Secrets, Input, Injection, Access) carry no severity. An `SR-n` that cites a preset keyword has no defined severity.
**Suggestion:** Add one clause: `a rule with no stated severity gives WARN`.

## Verdict Rationale

No finding is a bug that breaks users. The feature is off by default and advisory, and the tests pass. The T6 to T9 changes implement the three modes, the plan and build wiring, eight well-formed eval pairs whose rule ids exist, and a nightly workflow whose key check, opt-in skip and secret handling are sound. The `claude` CLI reads the model from an env var, not from the shell. The real weaknesses are in the measuring instrument. The runner can report a green zero when every call failed. Its catch match is loose, so the catch rate is flattering. Two `fixed` samples carry their own defects. Two new test checks are satisfied by text outside the section they claim to cover. Step 2c also departs from FR-10 without saying so. All are WARN or NOTE, so the verdict is APPROVED_WITH_NOTES. I recommend fixing the first two WARNs before the first nightly run, because their numbers will otherwise be read as the agent's quality.

APPROVED_WITH_NOTES
