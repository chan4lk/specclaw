## Base rules (always on)

Distilled from 538 review rounds on a production specclaw project. Most late-round majors were
defects left by a fix that patched only the case the reviewer named.

- **B1 Fix the class, not the case.** A fix for a reported defect must cover every variant of it: other
  spellings, locales and formats, every caller, and every second copy of the same logic. A fix that only
  makes the named example pass is a **major**: name the variant it misses.
- **B2 Every fix proves itself with a variant test.** A fix for a blocker/major ships a table-driven
  test over the variants (at least the named case plus two others). It must fail without the fix. A test
  that plants state by hand instead of driving the real path does not count. Missing → **major**.
- **B3 "Did not run" never reads as "clear".** A check, read, lookup or tool that failed, timed out or
  was skipped must surface as not run / unknown, never as an empty, passing or "not found" result.
  `None` or `[]` used for both "nothing there" and "could not ask" is a **major**.
- **B4 No second copy of logic.** A rule, threshold, mapping or parser written twice (often by a fix
  that patched one call site) is a **major** when the copies can disagree. Point at both.
- **B5 Pin what you read.** Data from an external source, model, list, or configuration that decides
  an outcome must record which version/revision/edition was read. An unpinned read that feeds a
  persisted result is a **major**.
- **B6 Fail closed on missing or malformed input.** Missing config, an unparsable response, or an empty
  required field must stop or flag, not fall back to a permissive default or a wider tolerance.
- **B7 Concurrency claims need a real race test.** A lock, claim or "exactly once" guarantee needs a test
  that runs two real workers/sessions. A single-session test that stays green with the lock deleted
  proves nothing → **major**.
- **B8 Secrets and untrusted input.** Hard-coded credentials, unescaped input into shell, SQL, HTML or
  paths, and user-controlled data written to logs are **blockers**.
- **B9 Merge and rebase damage.** Conflict resolutions that drop rows, duplicate instructions or revert
  a sibling change are **majors**. Compare against both parents.
- **B10 Scope.** Do not ask for features, refactors or renames outside the diff. Anything pre-existing
  and outside the diff is reported with `in_delta: false`.
- **B11 Unneeded code.** An abstraction, option, wrapper or layer nobody asked for, dead or unreachable
  code, and a speculative feature "for later" are a **major**: name what to delete. The smallest change that
  fully solves the task wins.
- **B12 Error handling.** Check each changed path for: a swallowed failure (an empty `except`/`catch`, an
  ignored exit code or error return); an external call with no timeout; a race between a check and its use
  or between two writers; a write that a crash can leave half done (write a temp file, then rename); and a
  retry or re-run that is not idempotent (it doubles a charge, a row or a message). Each that a concrete
  scenario shows is a **major**.

### Severity calibration

- **blocker:** data loss, security, or breaking a documented project law.
- **major:** wrong behaviour that a concrete test could show. You must give the scenario (input → wrong
  result). With no scenario, it is a minor.
- **minor:** naming, style, docs, records, process files, lint, line length, and missing nice-to-haves.
  Records, status files and lint are **never** major.
- Report one finding per root cause, not one per symptom or per reviewing pass.
