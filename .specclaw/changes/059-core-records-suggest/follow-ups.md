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
- [minor B3] `plugins/specclaw/lib/plugins.sh:29` `plugins_dismissed` sends awk errors to /dev/null and prints an empty list. An unreadable `config.yaml` therefore reads as 'nothing dismissed', and both the tip and the hook notice reappear. The impact is only an advisory line, but 'could not read' should not look the same as 'empty'. Return non-zero when the file cannot be read, and treat that as dismissed (stay silent). (round 6) <!-- fp:7b9225916278 -->
- [minor B6] `plugins/specclaw/bin/specclaw-suggest:36` The rewrite replaces the whole `  dismissed:` line, so a trailing comment on it is lost. For example, `dismissed: [review]  # keep for now` becomes `dismissed: [review, bf]`. Carry the comment over (the reader already strips it with `sub(/[[:space:]]*#.*$/...)`). (round 6) <!-- fp:01f8ac237906 -->
- [minor B6] `plugins/specclaw/bin/specclaw-suggest:43` `cat "$tmp" > "$CONFIG"` truncates `config.yaml` before it writes. If the write fails partway (ENOSPC, quota), the user's config is left short or empty. Check that `cat` succeeded and keep a backup, or use `mv` with `chmod --reference` if the reason for `cat` is to preserve permissions or symlinks. (round 6) <!-- fp:647a2d7b497d -->
- [minor B1] `plugins/specclaw/bin/specclaw-log-learning:287` `json_esc` blanks C0 control characters and escapes `\` and `"`, but it passes bytes that are not valid UTF-8 straight through (e.g. Latin-1 `\xe9` pasted from a terminal). The ledger line is then not valid JSON for strict readers. Replace invalid sequences (e.g. `iconv -c -f UTF-8 -t UTF-8`) before escaping. (round 6) <!-- fp:34c73d46f9ef -->
- [minor B3, final pass] `plugins/specclaw/lib/plugins.sh:29` An unreadable `config.yaml` reads as "nothing
  dismissed", so the tip and the hook notice reappear. Only an advisory line is affected.
- [minor B6, final pass] `plugins/specclaw/bin/specclaw-suggest:36` `--dismiss` rewrites the whole `dismissed:`
  line, so a trailing comment on it is lost.
- [minor B1, final pass] `plugins/specclaw/bin/specclaw-log-learning:287` Bytes that are not valid UTF-8 pass
  through `json_esc`, so a strict JSON reader can reject that lesson line.
- [minor B1] `plugins/specclaw/bin/specclaw-suggest:44` Replacing the in-place `cat "$tmp" > "$CONFIG"` with `mv` changes how the write behaves. If `config.yaml` is a symlink or hard link, `mv` replaces it with a regular file, and the old code wrote through the link. A config the user made read-only now gets overwritten, because `mv` only needs a writable directory. Keep the in-place write, or resolve the link target before the move. (round 7) <!-- fp:a6ad3095c59d -->
- [note, round 8] `plugins/specclaw/bin/specclaw-suggest` `--dismiss` resolves symlinks, refuses a read-only
  config and renames a mode-preserving copy over the real file, so a failed write never truncates it. A
  hard-linked `config.yaml` is split from its other links by the rename.
