# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [major B3] `plugins/specclaw-fleet/lib/feature-state.sh:6` The fix is applied to the work-item read and the PR read, but the records read still treats a failure as an empty result: `recs=... || recs='{"records":[]}'`. A failed or junk records read means no running, failed, or PR information. The member then falls through to pending/ready and is dispatched again, or is reported as not-opted-in. Fix: if records fails or is not an object with a records array, echo `?` and return. (round 2) <!-- fp:139893cf526a -->
- [minor B10] `plugins/specclaw-fleet/pipelines/dispatch.yml:21` Both templates now trigger on feature/*, but the path filter still includes only .specclaw/changes/*/state.json. The README and the feature skill say advance runs 'on every push to feature/<module>'. A hand merge or a conflict fix that leaves state.json alone does not advance the feature. Either widen the path filter for feature/* runs or correct the docs. (round 5) <!-- fp:d9dfa383c35d -->
- [minor B3] `plugins/specclaw-fleet/lib/optin.sh:46` whoami is called with changes[0]. specclaw-azdo-issue dies when that change directory does not exist, so a typo in the first argument aborts the whole optin with the misleading message 'could not read the identity behind AZDO_TOKEN', and the valid changes after it are not processed. Validate the change names first, or call whoami against one change that exists. (round 5) <!-- fp:3d10a35c3c0c -->
- [minor B4] `plugins/specclaw-fleet/lib/naming.sh:35` Four copies decide whether a name is a change or a feature, and their precedence differs. item_dir (naming.sh) and specclaw-azdo-issue's CHANGE_DIR prefer the changes/ directory. trigger_pushed_tree prefers the presence of changes/<x>/state.json. The pod's item_kind goes by FLEET_MODE. If a feature module shares its name with a change, the host gates on the change while the integrate pod reads the feature. Share one resolver, or refuse a feature module name that collides with a change. (round 5) <!-- fp:6ec803d282df -->
- [minor B3] `plugins/specclaw-fleet/image/integrate.sh:14` merge_base_ref treats any failed `git merge` as a merge conflict and tells the agent to resolve conflicts. A failure with no conflict behind it (unrelated histories, or local changes in the way) gets the same prompt. Check for unmerged paths (`git diff --name-only --diff-filter=U`) before handing it over, and otherwise record merge-ref-failed. (round 5) <!-- fp:c56a9d15f1b1 -->
- [minor B4] `plugins/specclaw-fleet/lib/feature-run.sh:21` Two places duplicate logic that has a shared helper. First, the conflict-retry check matches tags with a substring test (`contains("fleet:conflict-retried")`) while feature-state.sh uses the exact-match wi_has_tag. Second, the rule for resolving changes vs features is written three times: item_dir in naming.sh, the CHANGE_DIR override in specclaw-azdo-issue, and trigger_pushed_tree. trigger checks for state.json, while the other two check for the directory. Use wi_has_tag for the tag check, and one shared existence rule for item resolution. (round 6) <!-- fp:a7fc937e46c9 -->

## Left open when the review loop was closed (operator decision, 2026-11-09)

- The fixes for the second final pass (round 6) were made after it and have not been re-reviewed:
  - an unknown member fails `advance`;
  - an `ls-remote` error stops `feature start`;
  - an existing PR reports, and publishes, its real draft state;
  - one tag helper and one rule for resolving changes vs features.
- A member counts as merged only through its completed PR into `feature/<m>`. A hand merge made outside that PR is not detected (operator decision: PR-only).
- `advance` runs on merges into `feature/<m>` that change a `.specclaw/changes/*/state.json`. Any other merge needs `feature start <m>` to re-queue it.
- No live end-to-end run of a feature yet: demo-studio's 002–007 are the planned first run.
