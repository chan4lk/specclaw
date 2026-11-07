# Follow-ups: 049-fleet-runner-dispatch

- (review r1, minor) Agent output goes only to `/fleet/status/agent.log` on an emptyDir, so it is lost with the pod. Deliberately **not** echoed to the container log yet. Anyone with `pods/log` could then read anything the agent printed, including a token surfaced by prompt injection. Decide on redaction, or ship the log to the work item as an attachment, before exposing it.
- (verify) The ShellCheck gate scans only `plugins/*/bin`. The fleet `lib/`, `image/` and `tests/` scripts are clean at warning level today but are not gated in CI. Extend `shellcheck-gate.sh`.
- (design) A reaper that marks work items stuck in `Running` or `Dispatched` as `Failed` when their Job is gone or failed without a SIGTERM.
- (design) Workload identity instead of the `fleet-azdo` PAT for clone, push and PR.
- (smoke) A first real image build and cluster run are still owed: the plugin install syntax in the Dockerfile, the Squid allowlist hosts for Codex token refresh, and NetworkPolicy enforcement on K3s.
