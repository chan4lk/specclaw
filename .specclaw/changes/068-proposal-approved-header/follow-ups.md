# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [minor B3] `plugins/specclaw/bin/specclaw-set-phase:294` If `mktemp` fails, the function returns 0 silently. If the flip is skipped because the temp file is empty, nothing is reported either. The state is recorded as approved while the header still reads Draft, and the user is told nothing. Emit `warn` on these paths so a skipped flip does not look like a completed one. (round 1) <!-- fp:aae63c4b65a0 class:other -->
- [minor B1] `plugins/specclaw/bin/specclaw-set-phase:298` The guard `[[ "$line" != *Approved* ]]` is a substring match. A header that contains the word Approved but is not an approval is never flipped. In addition, the flip only goes one way, so re-opening a proposal (`proposal pending`) leaves a stale `âœ… Approved` header. Match the exact approved token, and decide and test the reverse transition. (round 1) <!-- fp:9811fdecf2e0 class:other -->
- [minor B1] `plugins/specclaw/bin/specclaw-set-phase:305` `printf '%s\n'` adds a trailing newline to a final line that had none. When the header is flipped, this changes a line other than the header, which the tests claim never happens. No test covers a proposal without a trailing newline. (round 1) <!-- fp:8fac398cab12 class:other -->
