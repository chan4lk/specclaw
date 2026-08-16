# Code Review Report: 032-party-mode

**Reviewed:** 2026-08-15
**Model:** claude-opus-5
**Verdict:** CHANGES_REQUESTED

## Summary

12 findings: 1 BLOCK, 6 WARN, 5 NOTE

Suite status: `bash plugins/specclaw/tests/run-party-tests.sh` → **138 passed, 0 failed** (run locally).
`shellcheck-gate.sh` skipped locally (shellcheck not installed); NFR3 is unverified here and rests on CI.
`design.md` present — D8 reviewed. `tasks.md` carries `Files:` entries — D9 reviewed.

## Findings

### [BLOCK] plugins/specclaw/skills/propose/SKILL.md:21 — Correctness / Design adherence

**Problem:** The change ships an invariant and, in the same commit, the one caller that cannot obey it.
`plugins/specclaw/CLAUDE.md:153` states:

> **No party config value may be read any other way** — not with `yaml_val`, not with a `grep` in a SKILL.md, not with a one-off `sed`.

But `SKILL.md:21` is exactly that read, with no mechanism behind it:

```
4. **Party panel (conditional).** Read `party.enabled` from the `party:` block of `.specclaw/config.yaml`.
```

and three more at `:34` (`party.default`), `:38` and `:44` (`party.rounds`), `:51` (`party.block`).
`specclaw-party`'s dispatch (`bin/specclaw-party:826-832`) exposes only `panel`, `tally`, `report`, `-h` —
there is no `config` / `--get` subcommand, and `panel.json` records `tier`/`seats`/`dropped` but none of
`enabled`, `default`, `rounds`, `block`. So the model executing the skill has no `party_val`-backed way to
answer the question and must read the YAML by hand.

That is not a hypothetical hazard — it is the exact one this change was built to close, applied to the
master switch. In the shipped template, the first whole-file hit for `enabled:` is:

```
plugins/specclaw/templates/config.yaml:67:    enabled: false      # build.dynamic_agents
plugins/specclaw/templates/config.yaml:132:  enabled: true        # party.enabled
```

verified by `grep -nE '^[[:space:]]*enabled:' plugins/specclaw/templates/config.yaml | head -1` → line 67.
CLAUDE.md:140 already names this precise outcome: *"party.enabled reads `false` off a block seventy lines
above the one asked for, so party mode would be off while the config plainly says `true`."* Under `party_val`
the answer is `true`; under any of the readings SKILL.md leaves open, `false` is a plausible answer. The
failure is silent and matches NFR5's legitimate off state exactly — an operator who set `enabled: true`
sees a `propose` run that never mentions the panel, which is indistinguishable from the feature working
as configured.

**Fix:** Give the skill the reader the invariant requires. Smallest version: add a `get` subcommand to
`bin/specclaw-party` that is a thin wrapper on the existing `party_val` / `party_list`
(`specclaw-party get <specclaw_dir> <key>`, e.g. `enabled`, `default`, `rounds`, `block`), and change
SKILL.md steps 4, b, d and e to call it instead of describing a read. Pin it with a test in
`run-party-tests.sh` against the decoy fixture — `get enabled` must return `true` where a whole-file
reader returns `false`, which is the same shape as the existing AC15 case.

---

### [WARN] plugins/specclaw/bin/specclaw-party:398 — Correctness

**Problem:** A `domains` value that is a bare string rather than an array silently drops the security seat.
`json_pick_array` (`:185-189`) requires a literal `[`:

```
  grep -o "\"$2\"[[:space:]]*:[[:space:]]*\[[^]]*\]" | head -1 \
```

Verified: with `{"tier":"thin","domains":"security"}` the panel resolves to
`party-po, party-architect` and `panel.json` records `"domains": []` — no warning on stderr, and the
audit trail says the classifier flagged nothing.

`domains` is model-written, and this is the same failure class as deferred defect (b) (the case-sensitive
`grep -qx`, patched at `:398` with `-i` and tested at `run-party-tests.sh:286-299`) arriving from the other
direction: a model asked for a one-element list will sometimes return the element. The consequence is
identical and was judged worth fixing then — the specialist is silently not seated and the roster still
reads like a working thin panel. Neither `panel.json` nor stderr distinguishes "no domains" from
"domains I could not parse", so D2's three-way visibility does not apply here.

---

### [WARN] plugins/specclaw/bin/specclaw-party:155-163 — Correctness

**Problem:** `party_list`'s block-form branch requires the `-` to be indented, so a column-0 list — valid
YAML, and the form `yq`/`ruamel` emit by default — is silently read as empty:

```
      inlist && $0 ~ /^[[:space:]]+-[[:space:]]+/ { line=$0; sub(/^[[:space:]]+-[[:space:]]+/,"",line); print line }
```

Verified against a config of:

```yaml
party:
  always:
- party-security
```

→ roster `party-po, party-architect`; the forced seat vanishes with no warning. `party.always` is the
operator's escape hatch for exactly the case where the classifier under-reads a proposal
(design.md:282, "Classifier misreads depth … Mitigation: … `always` force-seating"), so a silently empty
`always` disables the mitigation on the run that needed it. The same branch backs `party.panel` under
`panel_mode: fixed`, where an empty result now warns (`:385`) — the `always` path has no equivalent.

Note that `party_val`'s window scan is not the problem: `/^[a-zA-Z_]/` does not match a leading `-`, so
the reader stays inside the party block. Only the item regex rejects the line.

---

### [WARN] plugins/specclaw/bin/specclaw-party:266-512 — Complexity

**Problem:** `cmd_panel` is 246 lines and carries argument parsing, cache validation, tier resolution
(five branches), seat resolution, ranking, definition-drop, clamping, growth, JSON assembly and atomic
write in one function. The charter's guideline is ~30 lines. Nesting reaches four levels at `:444-456`.

The seat pipeline in particular is a self-contained arithmetic unit — `:372-456`, tier table → union
`always` → rank → drop undefined → clamp → grow — that takes a tier plus config and returns a roster,
and it is the part the review brief calls out as "off-by-one or ordering bugs here are silent". Extracting
it would also make it directly unit-testable without a fixture tree, a proposal file and a stubbed
classifier.

---

### [WARN] plugins/specclaw/bin/specclaw-party:274 — Dead code / YAGNI

**Problem:** `--emit-classifier-request` is implemented (`:274`, `:354`), documented in usage
(`:34`, `:51-52`), and has no caller, no test, and an explicit instruction never to use it. Its only
mention outside the script is `skills/propose/SKILL.md:32`:

> Never pass `--emit-classifier-request`: plain `panel` already performs this handshake, and the flag re-emits the request even when `classification.json` already exists.

(That sentence is also inaccurate about its own subject: `:335` takes the `-s "$class_file"` branch before
the flag is ever consulted, so the flag does *not* re-emit once an answer exists — the code comment at
`:356-359` says so correctly.) `grep -rn emit-classifier-request plugins .github` returns only the
declaration, the usage text and that prohibition. No `run-party-tests.sh` case exercises it. Per FR2/FR7
nothing asks for a second entry point to the handshake; the exit-10 path at `:354` already provides it.

**Fix:** Delete the flag, its two usage lines, and the SKILL.md prohibition that only exists because the
flag does.

---

### [WARN] plugins/specclaw/tests/run-party-tests.sh — Test quality

**Problem:** AC13 has no assertion anywhere in the suite. The header scopes it out —

```
# seat resolution (AC1-AC3, AC5, AC6), the fail-loud fallback (AC4), the
# override/cache paths (AC7, AC8), the block-scoped config reader (AC15), the
# verdict tally (AC9, AC10) and the report grammar the existing parsers read
# (AC11, AC12), plus Edge Cases 1-7, 9 and 10.
```

— and every fixture charter is synthetic (`mkfixture`, `:124-133`, `model: charter-${seat#party-}`), so the
six real files under `plugins/specclaw/agents/` are never read by a test. This is the cheapest possible
bash check (frontmatter delimiters plus `name`/`description`/`tools`/`model`, and the six expected model
values) guarding a path that fails silently: `seat_model` (`:221-231`) falls through to the charter's
frontmatter for any seat absent from `party.models`, so a typo in a charter's `model:` line spawns that
seat on the wrong model with no error anywhere. The suite even asserts the *absence* of that fallthrough
(`:567`, `assert_no_grep "AC15 no seat fell through to the charter frontmatter"`) without ever checking
what the fallthrough would produce.

AC14 (non-overlap), AC16 (`enabled: false` writes nothing) and AC17's shellcheck half are likewise
unasserted; AC14 is genuinely hard to automate and AC17's CI half is satisfied by
`.github/workflows/ci.yml:34-35`. AC13 is the one with no excuse.

---

### [WARN] plugins/specclaw/bin/specclaw-party:706 — Correctness

**Problem:** When `party.rounds` is 2 and `findings-r2/` does not exist — the shape of a round-2 dispatch
that failed after round 1 succeeded — every round-1 finding is discarded and `tally`'s stdout token is
`APPROVED`. Verified with an upheld `### [BLOCK]` sitting in `findings-r1/party-po.md`:

```
$ specclaw-party tally .specclaw c
WARN: no findings directory at .../party/findings-r2 — tallying an empty panel
APPROVED
```

`SKILL.md:51` instructs the caller to *"Read the token; never recompute or second-guess it"*, so the token
is the authority, and here it says APPROVED over a live BLOCK on disk. There are two mitigations and they
are real — the stderr warning above, and `**Unheard:**` naming every seat in the report (`:795`) — but
neither reaches the token, and `:706` uses `warn` rather than `die` so nothing in the exit status
distinguishes this from a genuinely clean panel.

**Fix:** When `rounds` is 2, `findings-r2/` is missing or empty, and `findings-r1/` is non-empty, that is a
broken dispatch rather than an empty panel — exit 2 with a message naming both directories, the same way
`:302-303` refuses to classify a missing proposal rather than treating it as thin.

---

### [NOTE] plugins/specclaw/bin/specclaw-party:451-456 — Correctness

**Problem:** Two small gaps in the `min_seats` growth loop.

```
  for o in "${TIER_ORDER[@]}"; do
    if [[ "${#seats[@]}" -ge "$min_seats" ]]; then break; fi
```

(a) Growth appends, so the resulting `seats` array is no longer in tier order. With
`panel_mode: fixed`, `panel: [party-visionary]`, `min_seats: 3` the roster is written as
`party-visionary, party-po, party-architect`. Nothing downstream re-clamps, so this is cosmetic today —
but `:409-418` exists specifically to guarantee "clamping drops the tail deterministically however the
seats were assembled", and after growth that guarantee no longer holds.

(b) A `min_seats` larger than the number of definable seats is silently unmet: `min_seats: 9` yields 5
seats and no warning, while every other config error on this path warns (`:438`, `:426`, `:385`).

**Suggestion:** Re-run the `ranked` filter after the growth loop, and warn when the loop exits with
`${#seats[@]}` still below `min_seats`.

---

### [NOTE] plugins/specclaw/bin/specclaw-party:128-137 — Correctness

**Problem:** `party_val` hard-codes two-space keys and four-space sub-keys:

```
    subk == "" && $0 ~ "^  " key ":" { line=$0; sub("^  " key ":[[:space:]]*","",line); print line; exit }
```

A party block indented four spaces reads as entirely absent — verified: `min_seats: 4` at four-space
indent yields a two-seat panel, silently taking every default. This matches the `da_val` precedent the
design chose to follow (`specclaw-build:557-574`), and the shipped template is two-space, so it is
consistent rather than novel — worth recording only because the failure is total and silent for a
hand-edited config.

**Suggestion:** Relax the key match to `^[[:space:]]+` + key and the sub-key match to a strictly deeper
indent, or state the two-space requirement in the `party:` block comment in `templates/config.yaml`.

---

### [NOTE] plugins/specclaw/tests/run-party-tests.sh:558-564 — Test quality

**Problem:** Three assertions that cannot fail independently of the two above them:

```
for leak in "DECOY-top-level-models" "anthropic/claude-opus-4-8" "anthropic/claude-sonnet-5"; do
  if [[ "$vis" == "$leak" || "$po" == "$leak" ]]; then
```

`:555-556` already pin `vis == "fable"` and `po == "sonnet"` exactly, so no value of `$leak` can match
unless those two have already failed. They add three to the 138 pass count without adding coverage.

**Suggestion:** Drop the loop; `assert_eq` on the exact expected values is the stronger assertion and is
already there. If the intent is to document *which* wrong values were possible, a comment says it without
inflating the count.

---

### [NOTE] plugins/specclaw/bin/specclaw-party:546 — One-liner opportunity

**Problem:**

```
force_upheld() { if [[ "$1" == "1" ]]; then echo 1; else echo 0; fi; }
```

A three-branch wrapper around a comparison, called twice as `"$(force_upheld "$rounds")"` (`:710`, `:767`).

**Suggestion:** Pass `$rounds` straight to `scan_findings` and let the awk do the comparison
(`force == "1"` at `:583` becomes `rounds == 1`), which removes the function and one subshell per call.

---

### [NOTE] .specclaw/changes/032-party-mode/tasks.md:125 — Design adherence / Scope creep

**Problem:** T8 declares `plugins/specclaw/bin/specclaw-init` in its `Files:` list, and
`git diff main...HEAD --name-only` shows it was not touched. FR16 is nonetheless satisfied — `specclaw-init:26`
pipes `"$PLUGIN_ROOT/templates/config.yaml"` into `$SPECCLAW_DIR/config.yaml`, so the new `party:` block at
`templates/config.yaml:126-148` is seeded transitively — but a reader diffing the task's file list against
the branch sees an omission where there is none.

D9 otherwise passes: every changed file appears in a `Files:` list. The W4/T9 deferral is coherently
recorded — `tasks.md:5` states `**Total Tasks:** 8 (+1 deferred)`, `:136-152` gives the reasoning at the
wave, and `party.on_loop_halt` is explicitly named as the one dangling config key. The design-map entries
for `skills/loop/SKILL.md` and `bin/specclaw-loop` (design.md:174-175) are covered by that deferral.

**Suggestion:** Strike `specclaw-init` from T8's `Files:` and note that seeding is transitive via the
template copy.

## Verdict Rationale

CHANGES_REQUESTED, on one finding. The arithmetic this change exists to own is in good shape: the seat
pipeline's clamp/grow/rank order is correct under the cases I probed, `tally_counts` is the single place
the FR12 rule is written, `tally` and `report` genuinely share one scanner, the fence handling in
`scan_findings` and the `WITHDRAWN` demotion in `emit_findings` both hold against the `specclaw-loop:291`
grep, and the 138 assertions are mostly load-bearing — the two deferred defects were found by the suite
rather than by inspection, which is the sign of a suite that works. The panelist charters are the strongest
artifacts in the change; the out-of-mandate lists are genuinely disjoint and specific enough to do the job
D6 asks of them.

The block is that the change ships a rule and its first violation together. CLAUDE.md:153 declares
`party_val` the only permitted reader of the `party:` block, and `SKILL.md:21` then asks a model to read
`party.enabled` with nothing to read it with — against a template where the first whole-file `enabled:` is
`false` seventy lines earlier, which is the failure CLAUDE.md:140 already describes in full. Every other
config-collision surface in this change was closed carefully and tested with decoys; this one is open, it
is the feature's master switch, and its failure mode is indistinguishable from the feature being correctly
switched off. Adding a `get` subcommand over the existing `party_val` and pointing the four SKILL.md reads
at it is a small change, and it is the difference between an invariant and a comment.

The six WARNs are the ones I would fix before the follow-up W4 change rather than after: two silent seat
losses (a string-valued `domains`, a column-0 `always` list), a discarded round when round-2 dispatch
fails, a dead flag whose only documentation is an instruction not to use it, an unasserted AC13, and a
246-line function. None of them is wrong today under the shipped config; all of them are wrong quietly.
