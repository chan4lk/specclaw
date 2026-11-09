# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [major B3] `plugins/specclaw-fleet/lib/feature-state.sh:6` The fix is applied to the work-item read and the PR read, but the records read still treats a failure as an empty result: `recs=... || recs='{"records":[]}'`. A failed or junk records read means no running, failed, or PR information. The member then falls through to pending/ready and is dispatched again, or is reported as not-opted-in. Fix: if records fails or is not an object with a records array, echo `?` and return. (round 2) <!-- fp:139893cf526a -->
