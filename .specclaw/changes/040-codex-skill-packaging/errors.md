# Error Journal: 040-codex-skill-packaging

Build errors and their resolutions.

---

## [T4] Investigation 1 — Verification was PARTIAL because the Codex adapter validator did not assert its CI registration or root-routing contract.

**When:** 2026-09-20 06:00 UTC
**Status:** upheld
**Failure-Sig:** —
**Reproduce:** `bash plugins/specclaw/tests/run-codex-skill-tests.sh; ! rg -q '\.github/workflows/ci\.yml|Run Codex skill adapter tests' plugins/specclaw/tests/run-codex-skill-tests.sh` → exit 0
**Evidence:** The validator passed while its source contained no CI workflow reference; .github/workflows/ci.yml separately invoked the test at lines 73-74.
**Hypothesis 1 (upheld):** the validator only checked adapter text and absent directories, so CI registration and root-routing regressions could remain green
**Fix:** Assert the CI invocation, runtime checkout-root and canonical-plugin-root expressions, dynamic verb route, and that the adapter contains only SKILL.md. (commit `55c9484`)
**Proof:** bash plugins/specclaw/tests/run-codex-skill-tests.sh; bash plugins/specclaw/tests/shellcheck-gate.sh; bash plugins/specclaw/tests/run-description-lint-tests.sh all exit 0

---
