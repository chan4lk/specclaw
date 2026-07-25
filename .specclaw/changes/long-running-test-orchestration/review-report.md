# Code Review Report: long-running-test-orchestration

**Reviewed:** 2026-07-25
**Model:** claude-sonnet-4-6
**Verdict:** APPROVED_WITH_NOTES

## Summary

10 findings: 0 BLOCK, 6 WARN, 4 NOTE

## Findings

### [WARN] plugins/specclaw/bin/specclaw-run-long:142 — Correctness (reuse cache)

**Problem:** The dirty-tree detection uses `git diff --quiet` and `git diff --cached --quiet`, neither of which detects untracked files. A new file added to the working tree but not yet staged (`git add`) leaves `current_dirty="false"`, so `--reuse` will serve a cached result despite the working tree differing from the HEAD state the cache was recorded against. The spec says edge case 4 covers "uncommitted working-tree changes" without restriction.

```bash
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  current_dirty="true"
fi
```

A test file created but not `git add`'d — exactly the scenario described in the root-cause analysis ("the operator is testing") — escapes this check.

### [WARN] plugins/specclaw/bin/specclaw-run-long:155–175 — Correctness (reuse cache)

**Problem:** The reuse path finds the sidecar by `phase+slug` (newest_sidecar) but never compares the sidecar's stored `cmd=` value against the current command. The slug is the command sanitised to `[a-z0-9-]` and truncated to 40 characters. Two distinct long commands can produce the same 40-char slug, causing a false cache hit: the sidecar from command A is served as the result for command B without re-executing.

```bash
prior_sidecar=""
"$reuse" && prior_sidecar="$(newest_sidecar)"

if [[ -n "$prior_sidecar" ]]; then
  cached_head="$(sidecar_val "$prior_sidecar" head)"
  cached_dirty="$(sidecar_val "$prior_sidecar" dirty)"
  cached_exit="$(sidecar_val "$prior_sidecar" exit)"
  cached_log="$(sidecar_val "$prior_sidecar" log)"
  # ... no check of sidecar_val "$prior_sidecar" cmd
```

**Fix:** After extracting `cached_head`, also read `cached_cmd="$(sidecar_val "$prior_sidecar" cmd)"` and add `elif [[ "$cached_cmd" != "$cmd" ]]; then warn "--reuse: command mismatch — re-executing"; fi` before the "all checks pass" branch.

### [WARN] plugins/specclaw/bin/specclaw-run-long:190–195 — Correctness (process lifecycle)

**Problem:** There is a race between trap registration and `child_pid` assignment. The trap is set for INT/TERM, then the child is backgrounded, then `child_pid="$!"` is assigned on the next line. If SIGTERM arrives in the window between the `&` and the assignment of `child_pid`, the trap fires with `child_pid=""`. The guard `[[ -n "$child_pid" ]]` prevents the kill, but the child runs without supervision: it becomes an orphan until it exits naturally, and no sidecar is written reflecting the interruption.

```bash
trap '_cleanup_interrupt' INT
trap '_cleanup_interrupt' TERM

# ─── Execute detached ─────────────────────────────────────────────────────────

set -m
( set +e; eval "$cmd" ) >"$log_file" 2>&1 &
child_pid="$!"   # <-- signal between & and this line orphans the child
```

### [WARN] plugins/specclaw/bin/specclaw-verify:151–174 — Correctness (trap clobbering in acquire)

**Problem:** `e2e_acquire_slot()` unconditionally installs `trap 'e2e_release_slot' EXIT`. If a caller of `cmd_collect` had previously installed a different EXIT trap (e.g. a temp-file cleanup), that trap is silently overwritten. Although no such pre-existing trap exists in the current codebase, this is a latent correctness issue: callers cannot safely compose traps with `e2e_acquire_slot`.

```bash
e2e_acquire_slot() {
  local specclaw_dir="$1" slot=""
  slot=$("$BROWSER_LOCK" "$specclaw_dir" acquire) || slot=""
  case "$slot" in
    ""|none) return 0 ;;
  esac
  E2E_SLOT="$slot"
  E2E_SLOT_DIR="$specclaw_dir"
  trap 'e2e_release_slot' EXIT          # overwrites any pre-existing EXIT trap
  trap 'e2e_release_slot; exit 130' INT
  trap 'e2e_release_slot; exit 143' TERM
}
```

**Fix:** Capture the prior EXIT trap with `old_exit_trap=$(trap -p EXIT)` before overwriting, then chain in the new handler: `trap 'e2e_release_slot; '"$old_exit_trap" EXIT`.

### [WARN] plugins/specclaw/bin/specclaw-build:329–333 — Correctness (redirect order)

**Problem:** The inline fallback in `run_long_check` uses `>&2 2>&1`, which first redirects stdout to stderr then redirects stderr to where stdout currently points (i.e., the same stderr). Both streams end up on stderr, which is the intent. However the second redirect `2>&1` is redundant and misleading: when read by a maintainer, it looks like stdout and stderr are swapped relative to each other, not combined. This is distinct from the pre-existing call sites in the original `cmd_finalize` which had the same expression — this is a NEW function introduced by this change.

```bash
eval "$cmd" >&2 2>&1
```

The correct idiom for "send both stdout and stderr to stderr" is `>&2 2>&1` but a clearer and less error-prone spelling is `2>&1 >&2` (dup stderr first so >&2 points to actual stderr) or simply leaving stderr as-is and only redirecting stdout: `1>&2`. Given the intent is "all output to stderr", the inline path should use `>"$log_file" 2>&1 >&2` or just `1>&2`.

### [WARN] plugins/specclaw/tests/run-long-orchestration-tests.sh:1289–1300 — Test quality

**Problem:** Case 43 tests `count_of '--workers'` on the full output string, which includes the `systemd-run ... bash -c 'npx playwright test --workers=1'` wrapper text. The count of `--workers` occurrences includes both any occurrence inside a `bash -c` single-quoted string AND any injected flag. For a multi-project fan-out, `--workers=1` appears multiple times (once per project invocation) and the assertion `assert_eq "AC10 exactly one --workers flag is emitted" "1"` would fail even when the implementation is correct. The test fixture has no projects configured, so in this specific fixture there is only one invocation and the assertion passes — but it would silently fail to detect an over-duplication bug when projects are configured.

```bash
out="$(wrap_with "$CAP_STUB" "$d43" "$WORK/w43.err" 'npx playwright test')"
assert_contains "AC10 a playwright command gains --workers=1" "--workers=1" "$out"
assert_eq "AC10 exactly one --workers flag is emitted" "1" "$(count_of '--workers' "$out")"
```

The test is not vacuous — it correctly passes and fails for the single-invocation case — but the "exactly one" assertion would give false confidence if the same test were applied to a multi-project fixture.

### [NOTE] plugins/specclaw/bin/specclaw-run-long:125–126 — Naming

**Problem:** The variable `log_base` is computed but only used in the lines immediately following to derive `log_file` and `sidecar`. Using `log_base` as an intermediate is clear but the variable name `log_base` is visually close to `log_file`, making it easy to accidentally use the wrong one in a future edit.

```bash
log_base="${log_dir}/${phase}-${slug}-$$"
log_file="${log_base}.log"
sidecar="${log_base}.result"
```

**Suggestion:** No change required — this is the clearest way to express the derivation. NOTE level only.

### [NOTE] plugins/specclaw/bin/specclaw-verify:299 — Correctness (minor)

**Problem:** The `e2e_configured` detection searches for `e2e_command` and `e2e` as bare keys anywhere in the config file using `grep -qE "^[[:space:]]*${field}:"`. If a future config key begins with `e2e` (e.g. `e2e_timeout`) it would set `e2e_configured=true` even if `e2e_command` and `verify.e2e` are absent. This is not a current bug — only a fragile anchor for future config evolution.

```bash
if yaml_has_key "$config_file" "e2e_command" || yaml_has_key "$config_file" "e2e"; then
  e2e_configured=true
fi
```

**Suggestion:** Comment the exact keys this is looking for and why partial-key matches are acceptable (or tighten the regex to `^[[:space:]]*e2e:[[:space:]]` for the `verify.e2e` key).

### [NOTE] plugins/specclaw/bin/specclaw-verify:311–342 — Complexity

**Problem:** The `cmd_collect` function is substantially longer than 30 lines after this change (the e2e block from line 311 to 420 is ~110 lines). The e2e policy logic is correct and well-commented, but the nesting reaches 5 levels deep for the "execute and classify" path.

```bash
if [ "$e2e_configured" = true ]; then    # level 1
  if [ -z "$e2e_cmd" ]; then             # level 2
    ...
  elif [ "$e2e_policy" = "skip" ]; then  # level 2
    ...
  else                                   # level 2
    if [ -n "$failed_gates" ]; then      # level 3
      ...
    else                                 # level 3
      if [ -n "$BROWSER_LOCK" ]; then    # level 4
        ...
        if [ -n "$wrapped" ] && ...; then # level 5
```

**Suggestion:** Extract the "acquire slot, wrap, execute, release, classify" block into a helper function such as `e2e_run()` — this reduces `cmd_collect` to a decision dispatcher and moves the nesting to a purpose-named function. Not required; NOTE only.

### [NOTE] plugins/specclaw/bin/specclaw-run-long:180 — Simplicity

**Problem:** The reuse section uses `"$reuse" && prior_sidecar="$(newest_sidecar)"` to conditionally invoke `newest_sidecar`. Running a boolean variable as a command string (`"$reuse"` expands to `true` or `false`, both of which are valid shell builtins) works but is non-idiomatic and trips up readers unfamiliar with the pattern.

```bash
"$reuse" && prior_sidecar="$(newest_sidecar)"
```

**Suggestion:** `[[ "$reuse" == "true" ]] && prior_sidecar="$(newest_sidecar)"` — same semantics, clearer intent.

_(No findings for Dimension 9 (Scope creep): all modified files appear in the `files:` entries in tasks.md.)_

_(Design adherence Dimension 8: implementation matches design.md across all four seams: run-long mechanics, slow-test tier, wrap subcommand, PR-aware status. No divergence found.)_

## Verdict Rationale

There are no BLOCK findings. The six WARN findings cover two reuse-cache correctness gaps (untracked files not detected as dirty; sidecar `cmd` field not compared on reuse), a narrow process-lifecycle race (SIGTERM between trap set and child PID assignment), a trap-clobbering risk in slot acquisition, a misleading redirect idiom in the inline fallback, and a test assertion that gives correct results for its fixture but would give false confidence on a multi-project fixture. None of these are reachable under the expected call patterns in the current codebase, but each describes a real failure mode that future callers or config changes could trigger. The four NOTE findings are style and complexity observations. The implementation correctly handles all 17 edge cases from the spec, passes NFR1 (byte-identical default output), correctly applies the [L2] `|| true` guard on every `grep`/`head`/`sed` pipeline in command substitution, and uses no `jq` or external runtime dependencies beyond coreutils (NFR3).
