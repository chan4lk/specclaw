# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [minor B8] `plugins/specclaw-fleet/lib/feature-run.sh:38` feature_start uses the module name in a git path, a push refspec (`FETCH_HEAD:refs/heads/feature/$m`) and a branch name before it is checked against the `^[a-z0-9][a-z0-9-]{0,40}$` pattern that feature_waves enforces for plan, init and advance. Validate it up front, as the other subcommands effectively do. (round 1) <!-- fp:669b4fcf07b9 -->
- [minor B1] `plugins/specclaw-fleet/image/entrypoint.sh:5` SPECCLAW_PR_TARGET now defaults to FLEET_REF for every run. In specclaw-azdo-pr it takes priority over `git.base_branch`, so ordinary change runs that opened PRs into the configured base branch now target the dispatch ref. The README and SKILL do not mention this change. Export it only for feature runs, when FLEET_PR_TARGET is set or FLEET_REF starts with feature/, or document the change. (round 1) <!-- fp:69702fda32fc -->
- [minor B4] `plugins/specclaw-fleet/lib/common.sh:74` common.sh ends with a stray blank line after load_local_env. Lint only. (round 1) <!-- fp:24ecdb66cb12 -->
- [minor B4] `plugins/specclaw-fleet/image/integrate.sh:5` The integrate prompt now names the PR target as `${FLEET_PR_TARGET:-main}`. This is a second copy of the target rule. The real target comes from resolve_pr_target (FLEET_PR_TARGET, then a feature ref, then git.base_branch, then FLEET_REF) and runs after the prompt is built. The old prompt used SPECCLAW_PR_TARGET and matched. Build the prompt text after resolve_pr_target, from $SPECCLAW_PR_TARGET. (round 4) <!-- fp:dbeacb8008bb -->
- [minor B2] `plugins/specclaw-fleet/tests/cases/ac28_pr_target.sh:24` The precedence table does not cover the stated order. There is no row where a feature/* FLEET_REF is set together with git.base_branch, and none where a non-main FLEET_REF is used with no config. The only no-config row uses the default ref main, so it cannot tell the FLEET_REF fallback from a hard-coded main. Add those rows, plus trailing-whitespace and CRLF values. (round 4) <!-- fp:742271cb3456 -->

## Left open when the review loop was closed (operator: deadline, 2026-11-09)

- The round-4 fixes (trimming in the base_branch reader, the prompt wording, precedence rows) have not been re-reviewed.
- There are no test rows for a failed delete of the integration marker, or for a conflicting merge that carries a marker.
- The self-hosted overflow agent and KEDA are deferred (operator: Microsoft-hosted only).
