# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [minor B6] `plugins/specclaw-fleet/lib/settings.sh:12` The `[A-Za-z0-9+/_-]{52,}` heuristic matches any long path or name made only of those characters, for example a kubeconfig path. Every fleet command then dies with 'looks like a secret'. Exempt values for path-typed keys, or require the value to contain no `/` separators beyond a leading one. (round 1) <!-- fp:f85e91c566ea -->
