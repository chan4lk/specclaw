# Code Review Report: 067-fleet-push-retry

**Reviewed:** 2026-11-16
**Model:** claude-sonnet-5-5
**Verdict:** CHANGES_REQUESTED

## Summary

7 findings: 1 BLOCK, 2 WARN, 4 NOTE

design.md absent, skipping D8 (the spec's Approach section was used). D9: no file outside the spec's file map was touched (ac10_manifests.sh is listed but unchanged, which is fine).

## Findings

### [BLOCK] plugins/specclaw-fleet/image/workspace.sh:21 and image/tracker.sh:38 — Correctness (data loss)
**Problem:** `prepare_workspace` resumes from the remote branch whenever it exists (`if awk ... <<<"$heads"; then ... return 0`) and never looks at the bundle. A successful push then runs `rm -f ... work.{bundle,base}` (tracker.sh:38), so the bundle is deleted even though its commits were never pushed. The common sequence is:
1. The agent, or an earlier run, pushes the branch (the `pr-azdo` skill pushes).
2. A later run adds commits, and its push fails. Its bundle holds `BUNDLE_BASE..HEAD`.
3. The next run finds the remote branch, resumes from the older remote tip, ignores the bundle, pushes, and deletes the bundle.

The saved commits are lost without any warning, and this is the case the feature exists for. FR-8 and FR-9 as written allow this. The test `remote_wins` (ac41) pins the bad behaviour.
**Fix:** When both exist and the bundle verifies, resume from the remote branch, then fetch the bundle ref. Fast-forward to it if the remote tip is an ancestor of the bundle tip. If they diverge, keep the bundle, warn, and skip deleting it. Alternatively, delete the bundle on push success only when the pushed HEAD contains the bundle tip.

### [WARN] plugins/specclaw-fleet/image/draft-pr.sh:55-56 — Correctness (deadline path)
**Problem:** `on_term` calls `deliver deadline 143`. The new `|| { ...; finish 4; }` branch writes `state=failed exit=push-failed` and exit code 4, so a deadline kill whose push also fails no longer reports `deadline`. The record, which previously said `exit=deadline`/143, hides the deadline cause, and `on_term`'s own `record state=failed exit=deadline` is never reached. The push retry (up to 65 s plus repack) still fits inside the 600 s slack (`activeDeadlineSeconds: F_DEADLINE + 600`). T1 acknowledged this behaviour but nothing tests it.
**Fix:** Pass the cause through, for example `"exit=push-failed"` plus `deadline=1`, or `finish "$2"` when `$1 == deadline`. Add a test that sends TERM with `PUSH_FAILS=9`.

### [WARN] plugins/specclaw-fleet/image/workspace.sh:30-35 — Security / robustness (bundle input)
**Problem:** `work.base` is written by an earlier agent run (`--dangerously-skip-permissions`) and is used without validation. It reaches `git merge-base --is-ancestor "$base" HEAD`, with no `--` and no hex check, and the warning `echo "... base ${base:-<missing>} ..."`, which has no length cap. A base of `--something` is read as an option, and a multi-megabyte or multi-line file goes into the pod log. The ancestor check is not a security control, because `git bundle verify` already enforces prerequisites. On a malicious bundle: `fetch` takes only `refs/heads/$b`, and checkout cannot write outside the worktree. The content equals what the same agent could push to the remote branch, so I found no new trust boundary. The bundle is also mounted only by its own per-change `subPath`, in the agent container only.
**Fix:** `[[ "$base" =~ ^[0-9a-f]{40,64}$ ]]` before the ancestor check. Print only a truncated value in the warning.

### [NOTE] plugins/specclaw-fleet/image/tracker.sh:44-46 — Security (push_error)
**Problem:** Redaction is pattern-only: tokens of 40+ characters, `sk-ant-` and JWTs. Git stderr is the only source, and the clone URL cannot carry credentials (`https://u:p@h/r` is refused at dispatch). The auth header is passed through the env, not the URL, so a leak is unlikely. A short secret in a `remote:` hook message would still pass. The line is also uncapped in length before it goes into the work item field.
**Suggestion:** `| redact | cut -c1-500` when writing `push-error`.

### [NOTE] plugins/specclaw-fleet/image/tracker.sh:40 — Shell correctness
**Problem:** `p="${pauses[i - 1]:-${pauses[${#pauses[@]} - 1]:-0}}"` with a whitespace-only `FLEET_PUSH_PAUSES` prints `bad array subscript` to the log (checked on bash 5.3: it still yields 0). A non-numeric pause makes `sleep` fail, so the retries run back to back. The script runs `set -uo pipefail` without `-e`, so neither case aborts the push loop. Pauses are not validated and cannot be set from `fleet:` (no render), so only the image default is used in practice.
**Suggestion:** `read -ra pauses <<<"${FLEET_PUSH_PAUSES:-5 15 45}"; (( ${#pauses[@]} )) || pauses=(0)`.

### [NOTE] plugins/specclaw-fleet/k8s/bundles-pvc.yaml:6 — Design adherence
**Problem:** `namespace: specclaw-fleet` is hard-coded, and `fleet.namespace` is configurable. This matches `network-policy.yaml`, so it is consistent with the repo, but `doctor` checks the PVC in `$D_NS`. The README line should say that a non-default namespace means editing the file first.
**Suggestion:** One sentence in README/SKILL.

### [NOTE] plugins/specclaw-fleet/tests/lib/entry-env.sh:18-20 — Test quality
**Problem:** The `git bundle create/verify` and `fetch` calls are stubs. The empty-range failure (`bundle=none`), the ref format, and the real verify, fetch and checkout are untested by the suite. T3 ran them once by hand. The `push` stub appends `push` to `$TMP/pushes`, and `grep -c push` counts only push lines, so the AC-1 and AC-2 counts do fail if the loop is removed. That part is not vacuous. The subPath builder is only checked for one URL form (`o/p/r/049-x`); the legacy `visualstudio.com`, GitHub padding, `..` and `.git` segments are untested.
**Suggestion:** Add one real-git bundle round-trip case and a table test for `bundle_subpath` with `..`, `.git`, a two-segment URL and `%` characters. I checked the code by reading: `..` becomes `_..`, empty segments are dropped, and the allowed set excludes `/`, so there is no traversal.

## Verdict Rationale

The main change is sound. It adds retry with repack, redaction reusing the existing patterns with the remote URL carrying no credentials, a validated claim name and a `subPath` that cannot traverse, the agent-only mount, and tests that fail without the code. One BLOCK remains: the resume order plus unconditional bundle deletion can silently destroy the unpushed commits the feature is meant to keep, whenever the remote change branch already exists and is older than the bundle. The deadline-path masking and the unvalidated `work.base` are WARN-level.

**Verdict: CHANGES_REQUESTED** — 1 BLOCK, 2 WARN, 4 NOTE
