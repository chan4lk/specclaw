# Tasks: specclaw-fleet trusted-config check dies with SIGPIPE (exit 141)

**Change:** 055-fleet-trusted-config-sigpipe
**Total Tasks:** 1

## Tasks

- [x] `T1` — First-match readers that consume all input (settings, workitem, feature-graph, doctor-azure, workspace, report); `trusted_only_settings` returns 0; regression test with a demo-studio-shaped config (fails 141 on the old code)
  - Files: plugins/specclaw-fleet/lib/settings.sh, plugins/specclaw-fleet/lib/workitem.sh, plugins/specclaw-fleet/lib/feature-graph.sh, plugins/specclaw-fleet/lib/doctor-azure.sh, plugins/specclaw-fleet/lib/report.sh, plugins/specclaw-fleet/image/workspace.sh, plugins/specclaw-fleet/tests/cases/ac37_sigpipe.sh
  - Kind: impl
