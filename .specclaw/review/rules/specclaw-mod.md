## Repo rules: the specclaw-mod propose gate

- **R2 Gate errors fail open, by operator decision.** In `plugins/specclaw-mod`, when the propose
  gate itself throws (a read, the cwd, or the state update fails), it shows a toast and lets the edit
  run, in every mode. The operator chose this on 2026-11-02 over failing closed: a broken gate must
  never stop work. Do not report fail-open gate errors as a finding. Still report a gate that *runs*
  and reaches the wrong verdict, and any path where a gate error is not surfaced (no toast).
