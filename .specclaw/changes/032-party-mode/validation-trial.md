# Validation trial — do the roles actually disagree?

**Run:** 2026-08-15, after W2 (charters written), before W3 (wiring).
**Artifact under review:** `.specclaw/changes/029-staged-files-auditor/proposal.md`
**Seats:** `party-architect` (opus), `party-security` (opus), `party-po` (sonnet). Round 1 only —
each seat saw the proposal and its own charter, and nothing else.

This is the gate `tasks.md` named as worth running before W2–W4 were finished: **spec Open Question 1
and the top row of the design's risk table both say the feature is worthless if the roles converge.**
The cheapest way to find out is to run the charters by hand and read the output.

## Result: they diverge. 17 findings, no duplicate claim.

| Seat | Findings | What it found |
|------|----------|---------------|
| `party-architect` | 4 BLOCK, 3 WARN | Third parser of `tasks.md` file lists with no shared extractor; second copy of the mandatory-artifact set alongside the validator that owns it; removing PR creation from `build` needs co-changes the scope list omits; two of the four `suspicious` rules need diff-content judgement in the layer defined as having none; Layer 2's blocking decision has no named enforcer; `--strict`/`--json`/exit-code space undefined for a CLI with three callers; test plan covers one script and none of the four other mechanisms. |
| `party-security` | 6 BLOCK, 1 WARN | The gate is opt-in at exactly the site the proposal says cannot be trusted to opt in; **every policy input is read from the branch being judged**; untrusted branch content reaches an agent holding an unqualified `Bash` grant; a crashed or silent auditor is indistinguishable from an approval; the post-commit net fires after the secret is already committed and the only remedy is out of scope; Open Question 5 proposes restoring `git add -A` on the failure path; escalation stops preserving uncommitted work. |
| `party-po` | 1 BLOCK, 2 WARN, 1 NOTE | Layer 2 is priced as decoration while the proposal's own evidence shows Layer 1 catches every reported failure; recurring spawn cost unquantified; the `build` PR-removal is scope with unstated value; Open Question 6 (gitignore vs `junk_patterns`) names a cut line that should be resolved before three In-Scope items are built. |

## Overlap analysis — the thing being tested

Two subjects were touched by more than one seat, and in both cases the **claims differ along the axis
the partition was designed on**:

1. **Removing PR creation from `specclaw-build`.**
   - Architect: the scope list omits `/specclaw:auto`, `/specclaw:loop`, and the mcd scheduler, so a
     caller that ends its chain at a PR URL will end it at a pushed branch and never reach the gate
     — *solution → codebase*.
   - PO: the removal takes a user-facing convenience to plug a hole that stays pluggable, and its
     dependencies are unaudited — *solution → value*.
   Same subject, two non-substitutable objections. This is the collision the charters resolve
   explicitly ("PO owns how much, Architect owns how shaped"), and it held.

2. **Layer 2's enforcement.**
   - Architect: no component is named as reading the verdict and refusing to continue, so the block
     is either an unspecified script contract or a sentence a model must remember.
   - Security: every way of *not* producing `CHANGES_REQUESTED` — crash, timeout, malformed verdict —
     is a pass that looks identical to a healthy approval.
   Adjacent, not duplicate: one is a missing contract, the other is a fail-open default.

No finding from one seat could be moved to another seat's charter without violating that charter's
out-of-mandate list. **The partition is doing work.**

## Secondary result: the findings are good

The trial was meant to measure divergence, not to review `029`. It did both. The strongest single
finding — `party-security`'s second BLOCK — is a real design flaw that survived the proposal's own
authoring and review:

> The classifier reads its allowlist from `tasks.md` and its policy from `.specclaw/config.yaml`, and
> both live in the working tree the same agent is committing. The party the gate judges therefore
> writes the gate's rules, in the same commit.

with three concrete disarms, including: add `.env*` to `allowed_extra_paths` and the secret-file
bucket stops blocking. Its fix — read policy from the base ref, `suspicious` strictly dominates
`declared` — is actionable as written.

## What this does not establish

- **Round 2 was not run.** Whether rebuttal changes any verdict (spec Open Question 2 — "what fraction
  of round-1 findings get withdrawn?") is still unmeasured. If that fraction is near zero, `rounds: 1`
  is the honest ship.
- **`party-ba` and `party-visionary` were not seated.** BA and Visionary are the two roles most at
  risk of producing horoscopes, and the Visionary is the one holding the `fable` seat. Spec Open
  Question 7 ("does `fable` earn the seat?") remains open and should be answered the same way: run the
  Visionary charter at `fable` and at `sonnet` on the same artifact and compare.
- **Three seats, one artifact.** Divergence on one proposal is evidence, not proof. The classifier's
  tier calibration against the full 31-proposal corpus is still the cheap next check.

---

# Trial 2 — does `fable` earn the Visionary seat?

**Spec Open Question 7**, run the way it asked: the same charter, the same artifact
(`029-staged-files-auditor`), round 1, once at `fable` and once at `sonnet`. Nothing else differs.

## Result: yes, on a visible margin.

| | `fable` | `sonnet` |
|---|---|---|
| Findings | 5 WARN, 1 NOTE | 1 BLOCK, 2 WARN, 1 NOTE |
| Tokens | 39.9k | 32.3k |
| Wall clock | 146s | 84s |

**Two subjects overlapped** — the artifact set becoming a third hand-synced copy, and the
`junk_patterns` list — and even there the claims differed:

- On `junk_patterns`, `sonnet` found that the project-level list is *append-only*, so a project that
  legitimately commits `*.log` cannot override a shipped default. Concrete, local, correct.
  `fable` found that the list becomes **a shadow `.gitignore` that specclaw curates forever**, and
  that the day the gate merges, Open Question 6 gets answered by default rather than decided.
- On the artifact set, `sonnet` filed the omission of `staged-files-report.md`. `fable` filed the
  same omission and observed that **the proposal is itself the next change that trips on the
  duplication it introduces** — the general form of the specific bug.

**Two findings `sonnet` did not reach**, and both are the reason the seat exists:

1. *The config-key mirror teaches a template.* This is the second gate built as
   agent + report + `<x>_audit`/`<x>_block` pair + ship-with-block-false, and the proposal cites the
   first as justification. Two copies make a pattern; the contributor who builds the third copies it
   without reading a footnote. Config keys are the sticky part — once projects set
   `staged_files_audit`, consolidating gates means migrating keys specclaw does not control. *"Each
   copy is cheap; the family of copies forecloses the framework."*
2. *`--strict` publishes a contract before deciding it.* The flag is designed for CI systems outside
   specclaw's release cadence, and Open Question 1 (should `undeclared` block?) changes the exit
   status of every pipeline that adopted it. Deciding that question after adoption is no longer a
   config change; it is a breaking release.

Both are claims about **precedent and compounding**, not about this diff — which is exactly the
mandate boundary the charter draws ("Architect's horizon ends at the merge commit; Visionary's begins
there").

**Mandate discipline also differed.** `sonnet`'s single BLOCK — `staged-files-report.md` is missing
from the mandatory set — is a duplicated-fact/contract-specification finding, which the partition
assigns to the Architect. `fable` filed the same observation inside a future-change frame and stayed
in lane. A cheaper model on this seat does not just find less; it drifts into the seat next to it,
which is precisely the convergence the partition exists to prevent.

## Caveat

One artifact, one run, no rebuttal round. The margin is visible but not large, and `sonnet`'s output
was not weak — a cost-constrained project setting `party.models.party-visionary: sonnet` would still
get a useful seat. The finding is that `fable` earns the *default*, not that `sonnet` is unusable.

---

## Consequence for this change

W3 wiring proceeds. The panel produces distinct, evidence-anchored, actionable findings from
non-overlapping mandates, which is the premise the rest of the change rests on. The `fable` default
for `party-visionary` stands, with Open Question 7 answered on evidence rather than intuition.
