# Code Review Report: tracker-state-integrity

**Reviewed:** 2026-08-01
**Model:** claude-sonnet-4-6
**Verdict:** APPROVED_WITH_NOTES

## Summary

7 findings: 0 BLOCK, 4 WARN, 3 NOTE

## Findings

### [WARN] plugins/specclaw/bin/specclaw-set-phase:265 — Correctness

**Problem:** The `CHANGE` variable is interpolated directly into a double-quoted `sed` expression without escaping. A change name containing `/` (the sed delimiter), `&` (back-reference), or `\` will corrupt the replacement expression, causing `sed` to error or produce garbled output. The sed call sits after the atomic `mv` of `state.json` (line 255), so `state.json` is already written correctly when this path runs — the failure mode is a partial install where `status.md` is absent and the self-heal fails, leaving only `state.json`. The script catches the `sed` failure with `|| die`, so it fails loudly rather than silently, but the die at line 270 exits 2 after the correct `state.json` is in place.

```bash
sed -e "s/{{title}}/${CHANGE}/g" \
    -e "s/{{change_name}}/${CHANGE}/g" \
    -e "s/{{date}}/${today}/g" \
    -e "s/{{updated}}/${today}/g" \
```

Change names are conventionally slugified (lowercase, hyphens only), and the calling SKILL.md files enforce that convention. No input validation in `specclaw-set-phase` itself prevents a name like `foo/bar` from reaching this code path.

**Fix:** Either validate that `CHANGE` matches `^[a-z0-9][a-z0-9-]*$` before the template substitution, or escape `CHANGE` before splicing into the sed pattern (e.g. `"${CHANGE//\//\\/}"` for the slash delimiter, plus `&` and `\` escaping).

---

### [WARN] plugins/specclaw/bin/specclaw-set-phase:40 / plugins/specclaw/bin/specclaw-reconcile:41 — Correctness

**Problem:** Both new scripts use `set -uo pipefail` rather than `set -euo pipefail`. The omission of `-e` is intentional for the fail-open reads, and every critical write path is individually guarded with `|| die`. However, two specific spots can silently swallow failures without `-e`:

1. `AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"` (set-phase line 217) — if `date` fails, `AT` is set to the empty string and `build_record` emits `"at":""` into the JSON. Under `-e` this would abort; without it, a corrupt timestamp is silently written.

2. `BUILD_RANK="$(phase_rank build)"` (reconcile line 166) — if `phase_rank` returns non-zero (impossible today since `build` is in `PHASE_ORDER`, but fragile to future edits), `BUILD_RANK` is empty and every subsequent `-le "$BUILD_RANK"` comparison produces an arithmetic error that is silenced.

**Fix:** For item 1: add `|| die "date command failed"` after the `date` assignment. For item 2: the current code is safe as written, but adding `|| die "internal: build not in PHASE_ORDER"` makes the invariant explicit.

---

### [WARN] plugins/specclaw/tests/run-phase-state-tests.sh — Test quality

**Problem:** Acceptance criteria AC5 (a `pr`-phase change renders in `STATUS.md` without a network call), AC6 (a change without `state.json` renders byte-identically to the current implementation), and AC7 (corrupt `state.json` degrades gracefully in the renderer) are all specified in the spec and listed in the task notes but have no assertions in `run-phase-state-tests.sh`. They exercise `specclaw-update-status`, which the suite never invokes. The spec's own acceptance criteria list them without qualification. A reviewer inspecting CI green cannot confirm those three acceptance criteria are met.

**Fix:** Add a section in the suite that invokes `specclaw-update-status` against a synthetic `.specclaw/` tree, capturing its stdout output, and asserts:
- AC5: a change with `state.json` recording `phase:pr` renders as `🔀` without consulting `gh` (use the `SPECCLAW_STATUS_NO_PR=1` env var or the `NOGH` shim).
- AC6: a change with no `state.json` produces the same output as a run from scratch (byte-identical `cmp`).
- AC7: a change with a truncated `state.json` renders via fallback, exits 0, and writes a warning to stderr.

---

### [WARN] plugins/specclaw/bin/specclaw-reconcile:113-117 — Complexity

**Problem:** `state_field` is copy-pasted verbatim in three files (`specclaw-set-phase`, `specclaw-reconcile`, `specclaw-update-status`). The comment at reconcile line 113 acknowledges this explicitly ("Third copy of the reader…kept byte-identical on purpose") and the rationale is sound (no shared-sourcing convention). The `diff` between set-phase and the other two confirms the copies differ only in two comment lines (the `ensure_ascii=False` explanation). The risk is drift: a bug fix or feature change (e.g. supporting integer JSON values that today return `json.dumps` output) must be applied to all three by hand with no mechanical check that they stayed in sync.

**Fix:** No change required given the design constraint (standalone executables, no sourcing). The risk is noted; the comment at reconcile:113 documents the rule. A future change adding a `lib/specclaw-state-reader.sh` source-once helper could fix this properly but would be YAGNI for now.

---

### [NOTE] plugins/specclaw/bin/specclaw-reconcile:599 — Correctness

**Problem:** The guard `[ "$ONLY_CHANGE" = "archive" ] && die "'archive' is not a change"` catches the exact string `archive`, but a caller passing `archive/2026-07-01-old` would reach `[ -d "${CHANGES_DIR}/${ONLY_CHANGE}" ]` and succeed — `$CHANGES_DIR/archive/2026-07-01-old` exists. `reconcile_one` would then run on an archived change, contra edge case 7. This is a path-traversal via the positional argument.

```bash
[ "$ONLY_CHANGE" = "archive" ] && die "'archive' is not a change"
[ -d "${CHANGES_DIR}/${ONLY_CHANGE}" ] || die "no such change: ${ONLY_CHANGE}"
reconcile_one "${CHANGES_DIR}/${ONLY_CHANGE}"
```

In practice `ONLY_CHANGE` is operator-supplied, and the reconcile of an archived change is harmless (it would report `no drift`). The test suite only tests `"archive"` and a non-existent name.

**Suggestion:** Add `[[ "$ONLY_CHANGE" == */* ]] && die "change name must not contain '/': ${ONLY_CHANGE}"` before the directory check, or broaden the archive guard to `[[ "$ONLY_CHANGE" == archive || "$ONLY_CHANGE" == archive/* ]] && die "…"`.

---

### [NOTE] plugins/specclaw/bin/specclaw-reconcile:283-289 — YAGNI / Simplicity

**Problem:** The `DRIFTS` and `UNKNOWNS` bash arrays are declared at global scope and reset at the top of `reconcile_one` on every call. The `drift()` and `unknown()` appenders are two-line functions used only inside `reconcile_one`. Because the arrays are reset on entry, this is correct but requires the reader to mentally track the reset-at-top convention to be sure findings from one change do not bleed into the next.

```bash
DRIFTS=()
UNKNOWNS=()
drift() {
  DRIFTS+=("$1|$2")
}
unknown() {
  UNKNOWNS+=("$1|$2")
}
```

**Suggestion:** Declare `local DRIFTS=() UNKNOWNS=()` inside `reconcile_one` and move `drift()`/`unknown()` there as local functions (bash 4+ supports local functions). This eliminates the reset-convention dependency and makes the scope obvious. Minor; the current form is correct.

---

### [NOTE] plugins/specclaw/bin/specclaw-set-phase:40 — Naming

**Problem:** The script header says `set -uo pipefail` but the pattern in every other script in `bin/` (including `specclaw-update-status`, `specclaw-build`, `specclaw-verify`, `specclaw-pr`) is `set -euo pipefail`. A reader landing on this file for the first time has to re-read the comment at the top or audit the `|| die` chains to understand the omission is deliberate rather than a mistake.

**Suggestion:** Add a one-line comment immediately after `set -uo pipefail` explaining why `-e` is absent:

```bash
set -uo pipefail
# -e is intentionally absent: reads are fail-open (state_field always returns 0);
# every write that must not fail is individually guarded with || die.
```

## Verdict Rationale

The change achieves its core goal cleanly: `specclaw-set-phase` is verifiably the sole writer of `state.json`, the `--fix` path in `specclaw-reconcile` correctly distinguishes a failing `gh` call (`unknown`) from a successful empty result (`none`) and refuses to downgrade recorded state on an unobservable dimension, and the fail-soft wiring in both PR scripts meets FR9. The 172-assertion test suite is substantive and non-tautological — the shim-PATH technique for testing the jq-less fallback path and the `gh`-absent/`gh`-failing/`gh`-succeeding trinity are thorough. No security issues, no single-writer violations, and no logic errors were found. Four WARN findings remain: an unescaped variable in a `sed` pattern that fails loudly in a narrow edge case, the implicit `date`-failure silent empty-timestamp risk from omitting `-e`, missing test coverage for AC5/AC6/AC7 against `specclaw-update-status`, and the copy-pasted `state_field` with no mechanical sync check. None of these are blockers; all are improvements to correctness or future maintainability.
