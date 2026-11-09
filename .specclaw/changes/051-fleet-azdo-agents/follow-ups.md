# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [minor B8] `plugins/specclaw-fleet/lib/feature-run.sh:38` feature_start uses the module name in a git path, a push refspec (`FETCH_HEAD:refs/heads/feature/$m`) and a branch name before it is checked against the `^[a-z0-9][a-z0-9-]{0,40}$` pattern that feature_waves enforces for plan, init and advance. Validate it up front, as the other subcommands effectively do. (round 1) <!-- fp:669b4fcf07b9 -->
- [minor B1] `plugins/specclaw-fleet/image/entrypoint.sh:5` SPECCLAW_PR_TARGET now defaults to FLEET_REF for every run. In specclaw-azdo-pr it takes priority over `git.base_branch`, so ordinary change runs that opened PRs into the configured base branch now target the dispatch ref. The README and SKILL do not mention this change. Export it only for feature runs, when FLEET_PR_TARGET is set or FLEET_REF starts with feature/, or document the change. (round 1) <!-- fp:69702fda32fc -->
- [minor B4] `plugins/specclaw-fleet/lib/common.sh:74` common.sh ends with a stray blank line after load_local_env. Lint only. (round 1) <!-- fp:24ecdb66cb12 -->
