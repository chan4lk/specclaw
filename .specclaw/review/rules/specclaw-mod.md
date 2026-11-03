## Repo rules: the specclaw-mod propose gate

- **R2 Gate errors fail open, by operator decision.** In `plugins/specclaw-mod`, when the propose
  gate itself throws (a read, the cwd, or the state update fails), it shows a toast and lets the edit
  run, in every mode. The operator chose this on 2026-11-02 over failing closed: a broken gate must
  never stop work. Do not report fail-open gate errors as a finding. Still report a gate that *runs*
  and reaches the wrong verdict, and any path where a gate error is not surfaced (no toast).

- **R3 The gate is a guard rail, not a sandbox, by operator decision.** The propose gate exists to
  stop a model that *forgot* to propose from editing source. It is not a defence against a model
  that sets out to defeat it. The operator scoped it this way on 2026-11-02, after review round 16.
  Do not report as findings: writes crafted to make the mod's own reads fail (binary or malformed
  content, replacing `.specclaw` files or folders, exotic links), filesystem aliases beyond what
  `$.fs.stat` realPath resolves, or permission errors that `exists()` reports as absent. Any gate
  error already toasts and fails open (R2). Still report a plain, good-faith edit that reaches the
  wrong verdict.
