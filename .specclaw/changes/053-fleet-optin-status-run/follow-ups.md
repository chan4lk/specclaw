# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [minor B6] `plugins/specclaw-fleet/lib/settings.sh:12` The `[A-Za-z0-9+/_-]{52,}` heuristic matches any long path or name made only of those characters, for example a kubeconfig path. Every fleet command then dies with 'looks like a secret'. Exempt values for path-typed keys, or require the value to contain no `/` separators beyond a leading one. (round 1) <!-- fp:f85e91c566ea -->
- [minor B3] `plugins/specclaw-fleet/lib/doctor-azure.sh:46` `pipeline_var` returns an empty string whenever the pipeline file is missing, unreadable, or the key does not match the two-space-indent regex. `check_connections` then silently falls back to the default names. 'Could not read the pipeline YAML' becomes 'check the defaults', so doctor can print `ok` for connections the real pipeline does not use. Emit a skip or warning when `pipeline_file` is set or expected but cannot be read or has no matching key. (round 2) <!-- fp:ba52966b6cfd -->
