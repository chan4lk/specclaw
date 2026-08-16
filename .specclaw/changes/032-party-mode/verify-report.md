# Verification Report: 032-party-mode

**Verified:** 2026-08-15
**Verdict:** PARTIAL

## Summary

Sixteen of seventeen acceptance criteria are MET, verified by independent probes rather than by
trusting `run-party-tests.sh`. The suite itself is real evidence: a mutation that swaps `party_val`
back for `yaml_val` semantics turns it red with 61 failures, including the AC15 assertions it claims
to pin. AC17 is UNVERIFIED because `shellcheck` is not installed on this box and `shellcheck-gate.sh`
exits 0 without checking anything, so "shellcheck-clean" has not actually been demonstrated. Two
substantive issues sit outside the AC list: FR13's claim that `specclaw-loop`'s `extract_verdict`
reads the party report is false, and a `context.md` constraint (force base ten on digit runs read
from disk) is violated in the seat clamp.

## Acceptance Criteria

| AC | Status | Evidence |
|----|--------|----------|
| AC1 | MET | Stub `{"tier":"thin"}` → `panel.json` seats `party-po party-architect`, `tier_source: classifier`. Independent probe on a clean fixture using the shipped `templates/config.yaml`. |
| AC2 | MET | Stub `{"tier":"deep"}` (no domain flag) → `party-po party-architect party-ba party-visionary party-security`. Security seated by depth alone, per `bin/specclaw-party:398`. |
| AC3 | MET | Stub `{"tier":"thin","domains":["security"]}` → `party-po party-architect party-security` (3 seats). Suite additionally pins the case-insensitive match (`Security`/`SECURITY`/`SeCurItY`) and that a domain merely *containing* "security" does not seat it — `grep -qix` at `:398`. |
| AC4 | MET | Three paths probed, all exit 0, all `tier=standard` / `tier_source=fallback` with a stderr `WARN:`. Unknown tier `{"tier":"enormous"}` → `WARN: ... (got: 'enormous')`. Unparseable prose → `(got: '<none>')`. Classifier turn never answered (the non-zero-exit analogue) → `WARN: no classification.json after a classifier request`. Never `thin` in any case. |
| AC5 | MET | `max_seats: 3` on `deep` → 3 seats `party-po party-architect party-ba`; `dropped: party-security(max_seats) party-visionary(max_seats)`. Visionary drops before Architect as AC5 requires. See Gaps for a discrepancy with FR4's stated order. |
| AC6 | MET | `always: [party-security]` at tier `thin` → `party-po party-architect party-security`. `min_seats` growth loop at `:451-456` walks `TIER_ORDER` and skips already-dropped seats, so the floor cannot be violated. |
| AC7 | MET | `--panel deep` with **no** `classification.json` present on disk returned exit 0 and a 5-seat roster with `tier_source: override` — the classifier branch at `:335` was never reached (reaching it would have exited 10). `panel_mode: fixed` likewise resolved with `tier_source: fixed` and exit 0 with no classification file. Suite asserts the same via a sentinel. |
| AC8 | MET | After a `deep` panel was written, `classification.json` was deleted and `panel` re-run: exit 0, identical 5-seat roster, no exit-10 request. Cache hit gated on `sig` + `schema_version` at `:310-318`. `--repanel` clears the marker at `:319`. |
| AC9 | MET | Fixture with one `**Status:** upheld` BLOCK → `CHANGES_REQUESTED`. Same fixture with that BLOCK marked `**Status:** withdrawn — retracted` → `APPROVED`. Independent probe, not the suite. |
| AC10 | MET | Upheld WARNs from `party-po` + `party-ba` → `APPROVED_WITH_NOTES`; single upheld WARN from one role → `APPROVED`. Boundary also probed: 2 WARN from one role → `APPROVED`, 3 WARN from one role → `APPROVED_WITH_NOTES`, matching the `roles >= 2 \|\| most >= 3` rule at `:623`. |
| AC11 | MET | As literally written ("`extract_verdict`-**style** regex `^\*\*Verdict:\*\*`"): `grep -E '^\*\*Verdict:\*\*'` on a generated report returns `**Verdict:** CHANGES_REQUESTED`, and `grep -cE '^### \[BLOCK\]'` returns `1` with one upheld BLOCK. **Caveat:** the actual `extract_verdict` function (`bin/specclaw-loop:167-179`) returns `UNKNOWN` on a party report — see Gaps. |
| AC12 | MET | Withdrawn WARN appears under `## Dissent` rewritten as `### [WITHDRAWN WARN]`; `## Findings` carries only the upheld BLOCK; whole-file `grep -cE '^### \[BLOCK\]'` = 1, so the demoted token keeps a withdrawn BLOCK out of the count (`emit_findings`, `:647-658`). Verified on a full end-to-end run. |
| AC13 | MET | All six charters parse as valid frontmatter with `name`, `description`, `tools`, `model` (python3 check, no key missing). Models: `party-classifier` haiku, `party-ba` sonnet, `party-po` sonnet, `party-architect` opus, `party-security` opus, `party-visionary` fable — exactly the spec's list. All six carry `tools: [Read]`. |
| AC14 | MET | All five panelist charters read in full. Each has `# Mandate` (five numbered probes) and `# Out of mandate`. The out-of-mandate lists are genuinely disjoint: every seat names the other four's territory and hands it back by name, and the four collision points are adjudicated explicitly in both directions — Architect vs Security ("an unspecified error contract is theirs; an error contract specified to fail open is yours"), Security vs Visionary (irreversibility of *runtime effects* vs of *design commitments*), PO vs Architect ("reuse the existing mechanism" is a structure finding, not a cost finding), Architect vs BA (test strategy vs falsifiability of criteria), PO vs Visionary (expensive to *build* vs expensive to *live with*). Wording/naming is assigned to no seat by design in all five. No mandate probe could be moved between seats without violating the receiving seat's exclusion list. |
| AC15 | MET | Verified twice. (a) On the **shipped** `templates/config.yaml`, which does carry a top-level `models:` block at line 11: `party_val` returns `fable` for `models.party-visionary` and correct values for all 14 party keys, while the shared `yaml_val` returns `false` for `party.enabled` (reading `build.dynamic_agents.enabled` seventy lines above) — the collision is real, not hypothetical. (b) Mutation test: replacing `party_val` with `yaml_val` semantics turns the suite red with 61 failures, and the AC15 assertions specifically report `expected 'fable', got 'DECOY-top-level-models'`. The test cannot pass under the defect it pins. |
| AC16 | MET | Traced `skills/propose/SKILL.md`. Step 4 is the only party reference in the skill: "Read `party.enabled` from the `party:` block of `.specclaw/config.yaml`. If `false` or not set, skip this step entirely — no `party/` directory, no prompt, no spawn, no mention of it in your reply." No other step (1–3, 5–9) touches party, and `grep -rn party-report` finds no other producer. With the step skipped, nothing in the propose path can create `party/` or `party-report.md`. See Notes on the limits of this evidence. |
| AC17 | UNVERIFIED | Registration: MET — `.github/workflows/ci.yml:34-35` adds "Run party-mode tests" → `bash plugins/specclaw/tests/run-party-tests.sh`, and the file is modified on this branch (`git diff main --stat` shows `.github/workflows/ci.yml \| 2 +`). Suite: passes 138/138, no network, no `jq` (`grep -n '\bjq\b'` finds only a comment). **Shellcheck: not demonstrated.** `shellcheck` is not installed here; `tests/shellcheck-gate.sh:22-25` prints "shellcheck not installed — skipping the gate" and exits 0. That exit 0 is the absence of a check, not the absence of findings. |

## Gaps and unverified claims

**AC17 — shellcheck-clean is UNVERIFIED, not passing.** `bash plugins/specclaw/tests/shellcheck-gate.sh`
exits 0 on this box solely because `command -v shellcheck` fails. `specclaw-party` is 832 new lines of
bash with heavy `awk`, array, and `set -u` use, and `shellcheck-baseline.txt` contains **no** entries
for it — which is consistent both with "clean" and with "never linted". The baseline is unmodified vs
`main`, so at least the change did not silence anything by appending. **To close:** install shellcheck
and run `bash plugins/specclaw/tests/shellcheck-gate.sh`, or read the GitHub Actions `shellcheck` job
on a pushed branch — CI installs it (`ci.yml:42-43`) and does gate on it, so the PR check will answer
this. I could not install it here (blocked, correctly, as an undeclared external package).

**FR13 contains a false claim, and AC11 inherits it.** FR13 states the report "uses the same shapes
`specclaw-loop` already reads (`bin/specclaw-loop:160-179` verdict extraction)". It does not.
`extract_verdict` finds the `^\*\*Verdict:\*\*` line and then extracts only from the alphabet
`PASS|FAIL|PARTIAL`; the legacy whole-file fallback is skipped precisely *because* a Verdict line
exists. Run against a generated `party-report.md` it returns `UNKNOWN`:

```
extract_verdict(party-report.md) = UNKNOWN
```

This is unfixable without contradicting FR13's own report grammar, which mandates
`APPROVED|APPROVED_WITH_NOTES|CHANGES_REQUESTED`. So AC11 under the strong reading ("the verdict must
be extracted by `specclaw-loop`'s `extract_verdict`") is **not satisfiable jointly with FR13**, and no
implementation could have satisfied it. AC11 as *written* says "`extract_verdict`-**style** regex
(`^\*\*Verdict:\*\*`)" — the line-anchor shape, not the function — and that is genuinely satisfied,
which is why it is scored MET. **Operationally this is inert:** `extract_verdict` has exactly one
caller (`specclaw-loop:263`, on `verify-report.md`), and nothing anywhere feeds `party-report.md` to
it. **To close:** amend FR13/AC11 to say the report shares the *grammar* (line anchor + `### [SEV]`
headings) rather than the parser, or teach `extract_verdict` the party vocabulary if the loop is ever
pointed at a party report.

**FR4's stated drop order is not what ships.** FR4 says clamping drops "from the tail of the tier
order (Visionary first, PO/Architect last)". `TIER_ORDER` (`bin/specclaw-party:24`) ends
`... party-ba party-visionary party-security`, so **Security drops first, then Visionary** — confirmed
by probe (`max_seats: 3` on `deep` → `dropped: party-security(max_seats) party-visionary(max_seats)`).
AC5 only asserts "Visionary dropped before Architect", so the AC passes either way and no test catches
the difference. This is a real behavioural question, not a wording nit: under a tight `max_seats` the
security specialist is the first seat sacrificed. **To close:** decide which order is intended, then
fix either FR4's parenthetical or `TIER_ORDER`, and add an assertion that pins Security's position.

**`context.md` constraint violated — base ten is not forced.** `context.md:40` requires
`$((10#$n))` on any digit run read from disk. `min_seats`/`max_seats` come from `config.yaml` and are
used raw in arithmetic contexts at `:436` and `:444`. A config of `max_seats: 08` passes the
`^[0-9]+$` guard and then fails as octal:

```
bin/specclaw-party: line 436: [[: 08: value too great for base (error token is "08")
bin/specclaw-party: line 444: [[: 08: value too great for base (error token is "08")
OK: panel resolved — tier deep (classifier), 5 seats
```

The clamp is silently skipped and the operator gets two raw bash errors plus an unclamped panel, exit
0. Affects `08`/`09` only. **To close:** `min_seats=$((10#$min_seats))` after the regex guard, same for
`max_seats`, and a suite case for `08`.

**Version not bumped.** `plugins/specclaw/.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` are both `0.6.6` and neither is modified vs `main`
(`git diff main --stat` returns nothing for either). The project's `CLAUDE.md` requires a patch bump
on every PR, with both files in sync. **To close:** bump both to `0.6.7` as a separate `chore:` commit
before opening the PR.

## Notes

**FR15 is not implemented, and this is deliberate and documented.** Wave 4 (T9, the loop-halt surface)
was cut; `tasks.md:136-152` states the reasoning — the propose surface has two validation trials and
138 green assertions behind it, the loop surface has none. No AC covers FR15, so the cut does not move
the verdict. The one loose end is real and is named in `tasks.md`: `party.on_loop_halt` ships in the
config block (`templates/config.yaml:134`) and is read by nothing — `grep` finds no consumer. It is
inert dead config until the follow-up lands.

**Which ACs the suite does and does not claim.** `run-party-tests.sh` scopes itself honestly in its
header to AC1–AC12 and AC15 plus Edge Cases 1–7, 9, 10. It does **not** claim AC13, AC14, AC16 or
AC17, and does not silently pretend to. Those four are prose/wiring criteria; I verified AC13 by
parsing all six frontmatter blocks, AC14 by reading all five charters end to end, AC16 by tracing the
skill, and AC17 by inspecting `ci.yml` and the gate.

**The limit on AC16's evidence.** AC16 says "running `/specclaw:propose` end-to-end". I did not run a
live propose session — that needs a model turn. What I verified is that the *instruction* is
unambiguous and that no other code path can create the artifacts. The residual risk is a model not
following prose, which no script can guard. Related minor point: step 4 tells the model to read
`party.enabled` "from the `party:` block" but does not name `party_val`, while `CLAUDE.md` states "No
party config value may be read any other way — not with `yaml_val`, not with a `grep` in a SKILL.md".
The instruction is directionally right (it names the block) but is the one place the rule is stated as
prose rather than enforced; given `yaml_val party.enabled` returns `false` on the shipped config, a
future author who reaches for the shared helper here turns party mode off while the config says `true`.

**Things checked that nobody asked about, all clean.** The shipped `templates/config.yaml` `party:`
block parses correctly through the script's own `party_val`/`party_list` for all 14 scalar keys and
both list forms (`panel` inline `[a, b]`, `always` empty). `specclaw-init` needs no change for FR16 —
it seeds config by `sed`-templating `templates/config.yaml` wholesale (`bin/specclaw-init:23-26`), and
a fresh `specclaw-init` run produces a `.specclaw/config.yaml` containing the full party block. Full
end-to-end from a clean fixture works: handshake exit 10 → write `classification.json` → `panel`
(5 seats, correct per-seat models from `party.models`) → `tally --json` → `report`. Edge cases probed
directly and all correct: EC1 (missing and empty proposal both exit 2 with a clear message, never
classified as thin), EC2 (JSON inside a fenced block wrapped in prose parses without falling back),
EC3 (`party-nonesuch` warned, dropped, recorded as `no-definition`, panel proceeds), EC9 (editing
`proposal.md` after `panel.json` exists re-triggers the classifier — exit 10 — while an unedited one
hits cache), EC10 (a rationale containing escaped quotes, a newline and a backslash round-trips
through `--json` and validates under `json.load`). `shellcheck-baseline.txt` is unmodified vs `main`,
satisfying the `context.md:107` constraint.
