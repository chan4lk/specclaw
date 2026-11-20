# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [minor B2] `plugins/specclaw/tests/run-quality-scan-tests.sh:90` The row precondition `$size -gt $(getconf ARG_MAX)` is still a weak proxy. `$size` is the byte count of the fake lizard output plus the jscpd report, not the size of the funcs.json, dup.json or clones.json tables the scan hands to jq. The fixtures clear 2 MiB with roughly 25 to 50 percent margin. On a host where getconf ARG_MAX is larger (Linux with `ulimit -s unlimited` reports up to about 6 MB), the precondition fails and the row reports a false failure, even though the real per-argument limit (MAX_ARG_STRLEN, 128 KiB) is still exceeded. Either drop the ARG_MAX comparison and assert the property directly (for example, run the scan under a small `ulimit -s`), or compare against the size of the table actually produced. (round 3) <!-- fp:a510e11d1a5b class:other -->
