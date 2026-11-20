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
- **B8 Secrets and untrusted input.** Hard-coded credentials, unescaped input into shell, SQL, HTML,
  paths or outbound URLs, and user-controlled data written to logs are **blockers**.
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
- **B13 Access control.** An endpoint or handler that does not check who the caller is, or that they own
  the resource it reads or changes, is a **blocker**. Access must be denied by default.
- **B14 Errors leak.** A stack trace, exception message or other internal detail sent to the client is a
  **major**. Fail closed with a generic error.
- **B15 Weak password storage.** Home-made crypto, or a password stored with a plain or fast digest (MD5,
  SHA-1, SHA-256) instead of Argon2id, bcrypt or scrypt, is a **blocker**.
- **B16 Dev bypass.** An env flag, header or hard-coded value that skips or weakens authentication, or a response
  that returns a one-time code or secret, is a **blocker**. It must refuse to start in production.
- **B17 Session lifecycle.** A logout or credential change that leaves the user's other sessions valid is a **major**.
- **B18 Account enumeration.** A sign-up, sign-in or reset whose status, body or timing differs for an existing and a
  new account, or a lookup that answers differently for a missing and a forbidden resource, is a **minor**.
- **B19 Code lockout.** A one-time code check with no cap on total failed attempts, so it can be guessed over time,
  is a **minor**.
- **B20 URL allowlist.** A URL or host allowlist checked with a substring or regex on the whole string instead of the
  parsed hostname (SSRF) is a **major**.
- **B21 Fail-open access check.** An ownership or role check that is skipped when the caller's identity is missing
  (e.g. `if (user && user.id !== owner)`), or that tests the target's role instead of the caller's, is a **blocker**.
- **B22 Security setting falls back.** A security control (rate limit, token or origin check) that turns off or falls
  back to a permissive default when its setting is missing is a **major**. It must refuse to start instead.
- **B23 Identity from request data.** An identity, token or credential read from a header, body field or tool
  argument and used in place of the authenticated caller's identity is a **blocker**.
- **B24 Open redirect.** A redirect target taken from the request without checking it against local paths or
  targets registered for the client is a **major**.

### Severity calibration

- **blocker:** data loss, security, or breaking a documented project law.
- **major:** wrong behaviour that a concrete test could show. You must give the scenario (input → wrong
  result). With no scenario, it is a minor.
- **minor:** naming, style, docs, records, process files, lint, line length, and missing nice-to-haves.
  Records, status files and lint are **never** major.
- Report one finding per root cause, not one per symptom or per reviewing pass.
