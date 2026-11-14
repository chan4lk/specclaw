# Follow-ups

- **062-dash-pane:** add `dash` to `plugin_feature` in `plugins/specclaw/lib/plugins.sh` and the `status`
  call site (`specclaw-suggest .specclaw dash`, lean and full) when the `specclaw-dash` plugin ships. Its
  install check needs a `bin/specclaw-dash` command, or `installed()` must learn to look for a plugin with no
  `bin/`. Dropped from 059 by review round 1: a tip must not name a plugin that does not exist yet.
