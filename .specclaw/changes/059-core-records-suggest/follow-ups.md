# Follow-ups

- **062-dash-pane:** add `dash` to `plugin_feature` in `plugins/specclaw/lib/plugins.sh` and the `status`
  call site (`specclaw-suggest .specclaw dash`, lean and full) when the `specclaw-dash` plugin ships. Its
  install check needs a `bin/specclaw-dash` command, or `installed()` must learn to look for a plugin with no
  `bin/`. Dropped from 059 by review round 1: a tip must not name a plugin that does not exist yet.
- [minor B2] `plugins/specclaw/tests/run-suggest-tests.sh:52` The json_esc fix is tested with one detail string that mixes `\r` and ESC. The newly escaped CATEGORY and PRIORITY, and ACTION, get no hostile input. The same fix applied to a variant table (quote, backslash, `\r`, `\b`, `\f`, 0x01, in each field) would show whether every field is escaped. As written, removing json_esc from category or priority leaves the suite green. (round 2) <!-- fp:e7e7525981b4 -->
- [minor B2] `plugins/specclaw/tests/run-suggest-tests.sh:44` The sibling-key assertion checks only `  other: 1`. Row 5 (same-indent items followed by the top-level `next: 1`) never checks that `next: 1` survived the rewrite. Row 3, where the list is the last key, has no sibling to check. A writer that swallows the key after the list would pass these rows. Assert that the sibling line (`other:` or `next:`) is preserved for every row that has one. (round 4) <!-- fp:f82ab19b4ae3 -->
- [minor B4] `plugins/specclaw/bin/specclaw-suggest:38` The list-boundary rule (blank and comment lines continue the list, the next key ends it) is still written twice, once in the plugins_dismissed awk and once in the --dismiss awk. Only a comment in plugins.sh says they agree. The previous finding asked for one shared helper or at least one rule. The new rows pin the five listed shapes, but any later edit to one copy can drift again with nothing in code linking them. (round 4) <!-- fp:405efba3742b -->
- [minor B4, review round 4] `plugins/specclaw/bin/specclaw-suggest:38` The block-list boundary rule (blank and
  comment lines continue the list, the next key ends it) is written in two awk programs: the reader in
  `lib/plugins.sh` and the `--dismiss` rewrite. A comment links them, and the table of block-list rows in
  `run-suggest-tests.sh` pins five shapes through both. A later edit to one copy can still drift; a shared
  awk fragment would remove the second copy.
