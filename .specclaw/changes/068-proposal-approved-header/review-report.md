# Code Review Report: 068-proposal-approved-header

**Reviewed:** 2026-11-16
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

6 findings: 0 BLOCK, 3 WARN, 3 NOTE

design.md absent (bounded change; the spec's `## Approach` was used as the design). `reviews/` does not exist, so there were no earlier findings to dedupe.
The 15 manifests agree: every `plugin.json` (Claude and Codex) and every marketplace entry is 0.9.17.
The code is correct. The weaker part is the tests (third WARN).

## Findings

### [WARN] plugins/specclaw/tests/run-phase-state-tests.sh:1019 and :1024 — Test quality
**Problem:** Two of the H cases do not discriminate, so AC5 and the phase guard are not really pinned. I ran each mutation on a temp copy of the suite:
- **H5b.** The line is `assert_eq "H5b and every line is still CRLF" "$(wc -l <"$C/proposal.md" | tr -d ' ')" "$(grep -c $'\r$' "$C/proposal.md")"`. I removed `${cr}` from the rewritten line, so the header lost its `\r`. A direct byte count then showed 5 CRs in 6 lines, but H5b still PASSED (6 = 6). On this Windows Git Bash, `grep -c $'\r$'` counts a CR-less line as matching. H5a strips `\r` with `tr -d '\r'`, so it cannot catch the loss either. The result is that the CRLF behaviour (AC5, FR5) is untested on this machine, and the line-count comparison may be unreliable elsewhere too.
- **H6a.** The line is `run_sp "$SPECCLAW" h6a spec done`, which uses status `done`. The status guard alone already blocks it, so deleting the `[ "$PHASE" = "proposal" ]` half of the guard changes nothing. I confirmed that `spec approved` flips the header in that mutant, and no test asserts otherwise. AC6 asks for the phase case specifically.
**Fix:** For H5b, count CRs with `tr -cd '\r' <"$C/proposal.md" | wc -c` (I verified this gives 6 on the real code and 5 on the mutant), or compare against a literal CRLF expected file with `assert_same_file`. For H6a, use `spec approved` instead of `spec done`.

### [WARN] plugins/specclaw/bin/specclaw-set-phase:298 — Correctness
**Problem:** `if [[ "$line" != *Approved* ]]` treats any header containing the case-sensitive substring `Approved` as already approved, so `**Status:** Not Approved` is left alone. I ran this on a temp copy and the file was byte-identical after `proposal approved`. FR3 asks for exactly this word test, and the template only ever writes `🟡 Draft`, so this is a hand-edit edge, not a normal path. "Unapproved", "unapproved" and "Approval" do not match, so only the capitalised word is affected.
**Fix:** Accept it and say so in the spec, or tighten the test to the forms FR3 names, e.g. `*"✅ Approved"* || *"🟢 Approved"*`. Do not add more logic than that.

### [WARN] plugins/specclaw/bin/specclaw-set-phase:308 — Correctness (write safety)
**Problem:** `cat "$flipped" >"$proposal"` truncates `proposal.md` and then writes. A kill or a full disk between the two leaves a truncated proposal. The `[ -s "$flipped" ]` check guards only an empty temp file, not a partial copy. The temp file is created in `$TMPDIR`, not beside the target, so a `mv` would not be atomic either, which is probably why `cat` was chosen. NFR2 accepts this pattern (it matches `specclaw-status-row`) and the file is a small, git-tracked document, so I judge the exposure low. Other things I checked:
- A read-only `proposal.md` fails at open, before truncation. The file is untouched, a `WARN:` is printed (plus bash's own "Permission denied" line), and the exit code is 0.
- The temp file is removed on every path except a signal between `mktemp` and `rm -f` (no trap), which leaves one stray file in `$TMPDIR`.
**Fix:** Optional. Create the temp file next to the proposal (`mktemp "${CHANGE_DIR}/.proposal.md.XXXXXX"`) and `mv` it, as `state.json` does a few lines above. It would then need mode care (mktemp is 0600), which is why leaving it is defensible.

### [NOTE] plugins/specclaw/bin/specclaw-set-phase:295-310 — Correctness (byte fidelity)
**Problem:** The `read`/`printf '%s\n'` loop adds a trailing newline when the last line of the file has none. I confirmed this with `'# x\n**Status:** Draft'`, which becomes `…✅ Approved\n`. It only applies when the header is changed, so FR3/AC3/AC4 byte-identity is unaffected, and the spec says "changes no other line". NUL bytes would also be dropped, which is irrelevant for markdown. No action needed; recorded because "changes no other line" is slightly looser than "byte-identical except the header".

### [NOTE] plugins/specclaw/bin/specclaw-set-phase:291-314 — Design adherence (D8, against the spec Approach)
**Problem:** The spec's `## Approach` says "awk to a temp file" but the code is pure bash (`while IFS= read -r`). The reason is sound: awk on this Windows machine strips carriage returns, which would break AC5. NFR3 (bash and awk only) is still met. The spec text is now stale. Placement is right: the block sits after `mv "$tmpfile" "$STATE_FILE"` and `trap - EXIT`, after the monotonicity `exit 3` and the `die`s, and before the status.md section, so an early exit in the status.md section cannot skip it. A refused backwards move correctly never flips the header.
**Suggestion:** Change "awk" to "bash read loop" in the spec Approach so the record matches the code. No code change.

### [NOTE] plugins/specclaw/tests/run-phase-state-tests.sh:994-1038 — Test quality (coverage)
**Problem:** What the other cases do pin, from mutations on a temp copy:
- Removing the whole call fails H1, H1b and H5a.
- Removing the first-line guard fails H1b, H2 and H4.
- Removing the `Approved` check fails H4.
- Removing the status guard (`approved` test) fails H6b.
H2, H3 and H6c-f pass with the code removed, which is expected for "nothing happens" cases. Remaining gaps, all minor:
- No case for `**Status:** Not Approved` (WARN above).
- No case for a change name with spaces or parentheses. I ran one by hand (`my change(1)`) and it works, since every expansion is quoted.
- No case for `specclaw-set-size` re-recording. I confirmed by hand that it flips a Draft header via set-phase and is idempotent.
- No case for a read-only `proposal.md`, so the NFR1 `warn` path is untested.
The suite's 81 baseline failures did not touch H1-H6: all 13 H assertions pass on the real code.
**Suggestion:** Optional: add the read-only case.

## Verdict Rationale

The code does what the spec asks. The first `**Status:**` line flips to `✅ Approved`, it keeps CRLF (I verified the bytes directly: 6 CRs in 6 lines), it skips already-approved headers, it never fails the transition (read-only file gives a warn and exit 0), and it runs only on `proposal approved`. It is also correct on re-approval through `specclaw-set-size`, and the block is placed before any later early exit. Scope is clean: the only files touched are the script, the suite, the propose reference and the version manifests. Nothing in this change is a BLOCK. The three WARNs are: tests that would still pass if the CR handling or the phase guard were broken, a loose substring match (`Not Approved`), and a truncate-then-write that the spec explicitly accepts. The base preset (no comments, one responsibility per function) is met by the new function.

**Verdict:** APPROVED_WITH_NOTES
