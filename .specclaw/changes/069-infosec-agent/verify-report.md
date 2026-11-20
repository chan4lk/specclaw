# Verification Report: 069-infosec-agent

**Verdict:** PASS

- AC-1: pass — `agents/infosec-reviewer.md` has front matter (`name`, `description`, `tools: [Read, Write]`, `model`) and names the four steps, the auth-flow questions and the five specclaw-specific checks; test `AC-1` passes.
- AC-2: pass — `templates/config.yaml` ships `workflow.security_review: false`; test `AC-2` passes.
- AC-3: pass — `references/full/verify.md` Step 3.52 spawns `infosec-reviewer` only when the flag is `true`, is advisory, and reports a failed run as NOT RUN; tests `AC-3` and `AC-3b` pass.
- AC-4: pass — the test deletes each required step, question, check and mode in turn and reports it by name.
- AC-5: pass — `ci.yml` registers `run-infosec-reviewer-tests.sh`.
- AC-6: pass — the agent's `# Output` section names `security-requirements.md` (with `**SR-1**`), `security/<T>.md` and `security-report.md`; the three `Mode plan/build/verify` items are mutant-tested.
- AC-7: pass — `plan.md` Step 3c spawns the agent in plan mode only when `workflow.security_review` is `true` (and not for a spike), before `spec.md`, and turns each `SR-n` into an acceptance criterion.
- AC-8: pass — `build.md` hands `security-requirements.md` to builders and Step 2c reviews entry-point tasks only, in build mode, advisory, with a `NOT_RUN` result when the agent fails.
- AC-9: pass — `verify.md` Step 3.52 passes `security-requirements.md` and the `security/` notes and counts unmet `SR-n`.
- AC-10: pass — 8 eval cases under `tests/evals/infosec/`, each with `vulnerable`, `fixed` and an `expect` of exactly `rule: <ID>|<Keyword>` naming an existing review-pack rule and preset keyword.
- AC-11: pass — the structural test breaks a case five ways (no `fixed`, no `expect`, unknown rule, unknown keyword, bad format) and reports each by case name.
- AC-12: pass — without `SPECCLAW_INFOSEC_EVALS` the runner skips with exit 0; with a stub `claude` it prints catch rate, false-alarm rate and model, scores a BLOCK on a fixed sample as a false alarm, and reports UNKNOWN and exits non-zero when calls give no answer, exit non-zero, or reps is not an integer.
- AC-13: pass — `ci.yml` registers `run-infosec-eval-cases-tests.sh`; `infosec-evals.yml` runs the runner nightly and on demand.

## Tests

```
run-infosec-reviewer-tests.sh         All passed   (22 checks)
run-infosec-eval-cases-tests.sh       All passed   (17 checks)
run-lint-meta-tests.sh                PASS: 51   FAIL: 0
run-description-lint-tests.sh         no new offences
run-change-size-tests.sh              PASS: 63   FAIL: 1   (T16; fails the same way on d0c33d7, before this work)
run-preset-check-tests.sh             fails on this machine: `ln: failed to create symbolic link` (Windows); presets and that test are untouched by this work
```

Not run: `shellcheck` is not installed here, so the shellcheck gate did not run. The eval runner has not been run against a real model (it costs API calls), so no catch rate or false-alarm rate exists yet. The plan and build modes have not been exercised by a model on a real change.

## Scope

The branch adds, on top of 069's first version: the three modes in `agents/infosec-reviewer.md`, Step 3c in `plan.md`, Step 2c and the payload line in `build.md`, the `SR-n` check in `verify.md`, the eval cases, the runner and its structural test, the nightly workflow, and `ci.yml`. The version bump is the existing 0.9.17 one. `code-reviewer.md`, the presets and the loop gates are unchanged.

**Code Review:** APPROVED_WITH_NOTES — 0 BLOCK, 5 WARN, 5 NOTE (see `review-report.md`). The actionable WARNs and NOTEs were fixed: the eval runner no longer reads a failed run as clear, the catch check matches only finding headings, `fixed` samples were corrected, the check for each build and verify path was scoped to its own section, and the results directory can be overridden.

**specclaw-review:** CLEAN — 8 rounds, final pass by opus at HEAD, last round 0/0/4 b/M/m. Rounds 5 to 7 found 5, 2 and 2 majors in the new eval runner and wiring, all fixed. The remaining minors (build and plan do not delete a stale output before spawning, the react-spa preset and rule wording differ, the proxy `fixed` sample uses a compound key, the nightly job timeout) are in `follow-ups.md`.
