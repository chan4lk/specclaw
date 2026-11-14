# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [minor B1] `plugins/specclaw/bin/specclaw-budget:41` estimate() skips any task without `Files:` before it looks at `Context:`. A task with a stated `Context: 90000` and no Files line is never flagged as over 60000. (round 1) <!-- fp:015647e97b7c -->
- [minor B3] `plugins/specclaw/lib/budget.py:112` set_context writes to a fixed `config.yaml.tmp` name. Two concurrent sets (the dash and the CLI) collide on that file. A failed write leaves the tmp file behind. The new file also takes the default mode and not the original's. For `roles: {}` the rewrite drops the trailing comment, and the shipped template's `roles: {}  # ...` form is not in the set test, which uses a config without that line. (round 1) <!-- fp:6ff6358086a9 -->
- [minor B1] `plugins/specclaw/lib/budget.py:34` The pipe fix allows only `head` and `tail` as extra commands. Other read-only filters on the same pipeline (`wc`, `grep`, `cat`, `sort`) are still denied in block mode, so the fix covers the named example and not the class. Either decide on a deliberate filter list and test it, or document that only head and tail are accepted. (round 2) <!-- fp:345b72d2887c -->
