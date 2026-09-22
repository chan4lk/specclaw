# Golden-Master Contract

This is the **only** stack-related artifact in the specclaw plugin. The
`bf-baseline`, `bf-replay` and `bf-bootstrap` bash collectors are 100%
stack-blind — they never detect a framework, never glob for a project file,
never invoke a toolchain by name. All stack intelligence lives in the
`bf-baseline-designer`, `bf-replay-mapper` and `bf-bootstrap-architect` agents,
which identify the legacy/rebuild stack themselves, per run — the first two by
reading the repo, the third by reading the decisions that chose it (section
(n.2)). Every generated artifact — harness code, replay tests, the target
foundation's own scaffold, manifests —
must conform to the field names and schemas below regardless of which
language or framework produced it. Never rename, reshape, or reformat any of
these; a rename breaks a downstream reader silently (the field just reads
back empty), not with an error.

**This document is a vocabulary, never a dictionary.** It fixes the *shape* of
what every stack must emit. It never lists a framework's exception types, a
project's error codes, or a mapping between them — those are per-project facts
that live in the target repo (`.specclaw/baseline/error-map.md`, section (h)),
authored at run time by the agents that actually read that repo. If you are
ever tempted to add a stack name or an error name to this file, that is the
signal you are writing the wrong artifact.

## (a) Fixtures

`.specclaw/baseline/fixtures/<GM-ID>.json` — exactly these top-level fields,
verbatim names, no others required, none omitted:

```json
{
  "scenario_id": "GM-019",
  "captured_at": "2026-08-07T10:15:00Z",
  "anchor_date": "2026-08-07",
  "legacy_commit_sha": "a1b2c3d",
  "runtime_version": "8.0.4",
  "normalized_fields": [],
  "input": { "...": "..." },
  "output": { "...": "..." }
}
```

- `captured_at` — ISO-8601 instant the fixture was actually captured.
- `anchor_date` — the calendar date every scenario's relative dates are computed
  from, so a replay on a different day reproduces the same absolute dates.
- `legacy_commit_sha` — the legacy repo's commit SHA at capture time.
- `runtime_version` — the legacy stack's own runtime/language version string
  (e.g. a .NET SDK version, a Node version, a Python version) — whatever the
  identified stack's own convention for reporting this is.
- `normalized_fields` — flat array of **canonical field paths** (section (g)),
  rooted at this fixture's own `output` object, excluded from replay comparison
  (see (b)). Every entry is resolved against this fixture's real `output` at
  record time: a path that matches **zero** fields is a hard
  `specclaw-bf-baseline record` error naming the dead path and suggesting the
  near-miss paths that do exist. A fixture with a dead normalization path is
  never silently accepted — a path that matches nothing normalizes nothing, so
  the field it was meant to exclude silently diverges on every replay.
- `input` / `output` — whatever shape the scenario's seam actually produces;
  no fixed schema beyond field-for-field mirroring in (b), plus the
  error-outcome fields in (b) whenever the seam can reject or throw.

## (b) Replay results

`actual/<GM-ID>.json` — its `output` field's names and nesting must mirror the
fixture's own `output` shape **field-for-field**. `specclaw-bf-replay compare`
diffs by field name; a renamed or restructured field reads as a spurious
divergence, not a build error.

### (b.1) Error outcomes — the business-class fields

Whenever a seam's captured behaviour is "succeeded, or was rejected," the
fixture-writer / result-writer generated for **any** stack must record these
three fields inside `output`, under these exact JSON key names:

| Field | Type | Meaning |
|---|---|---|
| `outcome` | `"OK"` \| `"REJECTED"` | Did the seam accept the input and complete, or refuse it? |
| `error_code` | string \| `null` | A stable, **project-defined** `SCREAMING_SNAKE` code naming *which* business condition rejected it. `null` when `outcome` is `"OK"`, and — only under (h)'s pending-question rule — when the condition genuinely could not be mapped yet. |
| `threw` | boolean | Did the seam signal the outcome by raising, versus returning a value? A seam that returns a rejection result object records `outcome: "REJECTED"` with `threw: false`. |

These three are **business-class**: they are what the legacy application
actually decided, expressed in language that survives a rebuild onto a
different framework. `error_code`'s vocabulary is per project and lives in the
target repo — see (h). Never invent a code here; never derive one from an
exception's type name.

### (b.2) Raw exception surfaces — the representation-class fields

The raw framework surface is still **recorded**, as evidence, under these four
exact key names — the same four for every stack, regardless of the source
language's own naming idiom (a Python writer, a Go writer, a JS writer all
still emit these literal keys):

`ExceptionType` · `InnerExceptionType` · `ExceptionMessage` · `InnerExceptionMessage`

`ExceptionType`/`InnerExceptionType` are compared by the identifier **after the
last `.`, `::`, or `/`** only — so a legacy `SomeNamespace.Foo.ValidationException`
and a rebuild `other.pkg.ValidationException` (or `pkg::ValidationException`, or
`pkg/ValidationException`) match on `ValidationException` alone.

**These four fields are representation-class: a difference in any of them, and
only in them, never by itself produces a `DIVERGES` verdict.** It is reported,
with both raw values retained (section (j)), because it is useful evidence —
but a rebuilt application legitimately raises differently-named exceptions with
differently-worded messages while making exactly the same business decision.
Comparing them as if they were behaviour is how a clean rebuild produces a
report full of divergences that mean nothing.

### (b.3) Business equality, stated once

Two outputs are **behaviourally equal** when every one of these agrees:

- `outcome`, `error_code`, and `threw`; and
- every other field that is neither representation-class (b.2) nor matched by
  the fixture's own `normalized_fields` (section (g)).

Nothing else. This set is computed by `specclaw-bf-replay compare` from the
declared data above — never enumerated per project, per stack, or by an agent.

## (c') `manifest.json` schema

`.specclaw/baseline/manifest.json` is written by `specclaw-bf-baseline record`
— bash-derived from `scenarios.md` and the fixture files, never agent-authored.

```jsonc
{
  "manifest_schema": 3,
  "plugin_version": "0.10.0",
  "generated": "2026-08-10",
  "generated_at": "2026-08-10T09:12:00Z",
  "project_root": "…",
  "total_scenarios": 31,
  "fixtures": [ /* one entry per captured scenario, fields below */ ],
  "missing_scenarios": ["GM-022"]
}
```

- `manifest_schema` — integer, currently `3`. **`specclaw-bf-replay resolve`
  hard-fails on a manifest that lacks this field or predates the *minimum*
  readable schema (`2`)**, before it creates anything, and names
  `re-run /specclaw:bf-baseline --record` as the fix. It never assumes a
  missing field means "the old default was fine."

  **Two floors, deliberately.** A change-scoped or `--all` run needs nothing
  from schema 3 and keeps reading a schema-2 manifest unchanged, so adopting
  the module hierarchy forces no project to re-record. Only a `MOD-###` run
  — which *is* a join on `module_ids` — requires `3`, and it fails with its
  own message saying so. A version bump that silently invalidated every
  existing baseline would cost every project a recapture cycle for a feature
  it may not use.
- `plugin_version` — the specclaw version that recorded this manifest, stamped
  at record time. `specclaw-bf-replay` stamps its own running version into
  `run-metadata.json` and the report header, so a mismatch between the two
  (a report rendered by v0.9.0 against a manifest recorded by v0.7.0) is
  visible on the report's face rather than inferred later. A mismatch is a
  WARN, not a failure — a stale *schema* is what fails.

Each `fixtures[]` entry carries:

- `status`: `VERIFIABLE | PROVISIONAL | SUPERSEDED`. `PROVISIONAL` means the
  fixture's underlying scenario traces to a business rule still blocked by an
  open pending question (see `templates/pending-questions.md`) — captured and
  replayable, but not yet a settled proof. `SUPERSEDED` means the scenario's
  own definition changed since this fixture was captured against it — it must
  be recaptured, and until it is, replaying it proves nothing about the
  scenario as currently written. `specclaw-bf-replay` propagates both into its
  verdict computation (section (j)); never a stack-specific concern.
- `module_ids`: `["MOD-002", "MOD-005"]` — every module whose `DR-###` rules
  this scenario pins, per (l). Extracted verbatim from the scenario's own
  declared `Modules` field, never re-derived here; `[]` is legal and means
  the project has no module map. **A scenario whose rules span modules
  carries all of them**, and `specclaw-bf-replay --module` selects it for
  every one (ANY-of).
- `seam_layer`: the fixture's capture layer, per (i) — extracted verbatim from
  the scenario's own declaration, never re-derived from prose.
- `outcome` / `error_code` / `threw`: lifted from the fixture's own `output`
  per (b.1), so a reader can see the recorded business decision without
  opening every fixture file.
- `normalized_fields_resolved`: `[{"path": "…", "matches": N}]` — proof that
  every declared normalization path actually resolved against this fixture's
  output. `record` refuses to write a manifest where any `matches` is `0`.
- `verifies_backlog_item`: **metadata, and a cross-check only — never a join
  key.** `/specclaw:bf-replay` resolves a `BL-0##` to its fixtures through the
  item's own acceptance-basis `DR-###` citations in `rebuild-backlog.md`
  matched against `business_rules_pinned` — the same chain
  `/specclaw:bf-rebuild-plan` computes each item's `**Verification:**` line
  from, so the two are testably equal. This field cannot carry that join: the
  pipeline's order records a baseline (A4) *before* the backlog exists (A5), so
  a first-recorded manifest necessarily holds the designer's `not yet
  backlog-linked` placeholder on every entry. `resolve` therefore ignores the
  placeholder silently and, when the field *is* populated and disagrees with
  the join, emits a `WARN` naming both sets without changing its selection —
  one of the two documents is stale and bash cannot know which. `record` fills
  it in best-effort from `rebuild-backlog.md` when that document exists,
  **never overwriting a value a scenario declares itself**, and nothing
  downstream may require the result.
- plus the existing `scenario_id`, `seam`, `business_rules_pinned`,
  `fixture_path`, `content_hash`,
  `scenario_content_hash`, `provisional_ref`, `captured_at`, `anchor_date`,
  `legacy_commit_sha`, `runtime_version`, `normalized_fields`.

## (c) ID permanence

`MOD-NNN` (modules), `GM-NNN` (scenarios), `DR-NNN` (business rules),
`CQ-NNN`/`SQ-NNN`/`UQ-NNN` (clarify questions), `BL-NNN` (backlog items),
`ST-NNN` (dependency-bypass stubs, section (m)), `IS-NNN` (item splits,
section (o)), `QI-NNN` (code-quality hotspots) are permanent once assigned —
never renumbered, never reformatted, across any regeneration or archive cycle.

`ST-NNN` and `IS-NNN` carry the same carve-out from the rest of this section:
their documents (`module-stubs.md`, `item-splits.md`) are **append/update-in-
place and are never archived**, on the same terms as `pending-questions.md` and
`clarifications.md`. So neither id ever becomes a tombstone — retiring a stub
or completing a split updates that entry's own `Status` line and leaves the
entry in place, because the record that an item was built out of order, or
built in halves, is the finding, and it outlives the stub or the split.

`QI-NNN` (code-quality hotspots, `templates/quality-issues.md`, produced by the
optional `/specclaw:bf-quality`) takes that same carve-out, for the same reason
and with one addition. Its registry is never archived while the `quality.json`
snapshot beside it *is* archived on every run — which is precisely why the
registry is a separate document rather than a section of the snapshot: an id
space that gets rotated with the evidence it labels is the silent re-pointing
this section exists to prevent. A hotspot that no longer exceeds its threshold
has its `Status` flipped to `resolved` and keeps its id and `First seen` date
permanently; it is never removed, because "this used to be a hotspot" is what
makes a module somebody cleaned up distinguishable from one that was never bad.
Identity is the entry's declared `Key`
(`metric|file|scope|module|start_line`), never the measured value — values move
on every commit, and keying on one would mint a fresh id per run and make two
reports months apart incomparable, which is the only thing a permanent id is
for. `scope` and `start_line` are what make two hotspots in one file distinct:
the measuring tool reports the short function name, so two overloads are one
string and every unnamed function is reported under one name, and the
four-field key that preceded this gave several hotspots one id and then deleted
all but one of them on the following run. `scope` is that name UNQUOTED — the
tool emits it as a quoted CSV field, and a key carrying the quotes makes
`"Login"` a different hotspot from the same `Login` measured by anything else;
a registry written before that was fixed is migrated in place, keeping every id
and `First seen` date. A renamed file yields a new `QI-NNN`
plus a resolved old one: inferring the rename would carry an id, and its whole
history, onto code nobody measured.

`QI-NNN` has one terminal status of its own, `superseded-duplicate`, and it is
the single exception to "never a tombstone" above. It marks an id that was one
of several sharing a key before the key could tell those hotspots apart, and it
names the id that now owns the hotspot in a **Superseded by:** field. Such an
entry keeps its number, its `First seen` date and the historical key it was a
duplicate under, is carried forward verbatim on every later run, and is never
re-judged — which is why it is a status rather than a deletion. Reshaping the
key is the only thing that can produce one, it is done by a recorded, dated
migration that maps ids rather than renumbering them, and where the record does
not decide which id owned which hotspot the collector stops instead of
guessing. Unlike every other id in this section, nothing reads a `QI-NNN` and
no command's behaviour changes because of one — it is a record, not a gate.

An id that no longer describes anything becomes a **tombstone** rather than
disappearing (`### MOD-004 — WITHDRAWN <date>, superseded by MOD-002`, and the
same shape for `DR`/`BL`/`GM`), so that any document still citing it fails
loudly instead of silently pointing at whatever now occupies that position. A
tombstoned id stays claimed forever and is never reused; `record` and
`harness-collect` skip tombstoned scenarios while still counting their ids
toward the next free one.

`MOD-NNN` and `GM-NNN` are both **reconciled** across regenerations rather
than regenerated: their producing collectors read the prior document *before*
the archive step and hand the agent an id-level roster to match against.
Without that, a re-run would silently re-point every fixture, manifest entry,
and module tag hanging off those ids — without changing a single hash.

## (d) `harness-manifest.json` schema

Written by `bf-baseline-designer` in harness mode, under
`.specclaw/baseline/harness/`:

```json
{
  "stack": "string — the identified legacy stack, e.g. \".NET 8\", \"Node 20 / Prisma\", \"Python 3.12 / Django\"",
  "build_command": "string or null — null if the stack has no separate build step",
  "run_command": "string — the command that runs the harness and produces fixtures",
  "fixtures_output_dir": "string — repo-relative path fixtures are written to",
  "runtime_version_source": "string — how runtime_version in each fixture is obtained, e.g. \"Environment.Version\", \"process.version\", \"platform.python_version()\""
}
```

## (e) `run-config.json` schema

Stubbed by `specclaw-bf-replay init-rundir`, completed by `bf-replay-mapper`:

```json
{
  "stack": "string or null — null until the mapper agent completes this file",
  "build_command": "string or null — null if the rebuild stack has no separate build step",
  "test_command": "string or null — null until the mapper agent completes this file",
  "results_dir": "actual",
  "evidence_exclusions": ["array of strings — glob patterns for this stack's own build/dependency output, e.g. [\"bin/\", \"obj/\"] or [\"node_modules/\", \"dist/\"]"]
}
```

`specclaw-bf-replay run-tests` fails loudly if `test_command` is still `null`
("mapper never completed run-config.json") rather than guessing a default.

## (f) `ui-manifest.json` schema

Written by `specclaw-bf-ui record` (Mode B — pure bash, no agent) at
`.specclaw/ui/ui-manifest.json`, from the human-captured PNGs under
`.specclaw/ui/screens/`:

```json
{
  "generated": "2026-08-10",
  "legacy_commit_sha": "a1b2c3d",
  "total_checklist_rows": 7,
  "screenshots": [
    {
      "scr_id": "SCR-001",
      "state": "default",
      "screen": "Main Dashboard",
      "file": ".specclaw/ui/screens/SCR-001.png",
      "sha256": "sha256:<64 hex>",
      "captured_at": "2026-08-10T09:12:00Z",
      "legacy_commit_sha": "a1b2c3d"
    }
  ],
  "missing": [
    { "scr_id": "SCR-002", "state": "validation-error",
      "expected_file": ".specclaw/ui/screens/SCR-002-validation-error.png" }
  ],
  "extra": [
    { "file": ".specclaw/ui/screens/notes.txt",
      "reason": "filename does not match the SCR-###[-state].png convention" }
  ]
}
```

- `scr_id` — the screen's permanent `SCR-NNN` id from `ui-inventory.md`.
- `state` — the state captured, matching its `screenshot-checklist.md` row
  (`default` for the plain view).
- `file` — repo-relative path of the PNG. Filenames follow
  `SCR-###.png` / `SCR-###-<state>.png`, validated mechanically; a file that
  violates it is reported under `extra`, never silently accepted.
- `sha256` — `sha256:<hex>` of the file's bytes, making the captured
  evidence tamper-evident exactly as a fixture's `content_hash` does. Empty
  only when the machine has no `sha256sum`/`shasum`, which `record` warns
  about loudly rather than passing off as sealed evidence.
- `captured_at` — ISO-8601 UTC **filesystem mtime of the PNG at record
  time**. A PNG carries no trustworthy capture timestamp and nothing in
  specclaw parses image internals, so this is a labelled proxy, not a
  claim about when the human took the shot.
- `legacy_commit_sha` — the legacy repo's HEAD **at record time**. Same
  caveat: it dates the recording, not the capture.
- `screen` — the human-readable screen name, carried through from the
  checklist for readability. Convenience plumbing, the same tier as
  `manifest.json`'s `provisional_ref` — a reader may use it, nothing
  computes from it.
- `missing` / `extra` — normal reported states, never errors. A checklist
  row with no file is `missing`; a file matching no row is `extra`.

`SCR-NNN` (screens) and `TK-NNN` (design-token groups) are permanent once
assigned — never renumbered, never reformatted, across any regeneration or
archive cycle — on exactly the same terms as the ID families in (c). A
screen that no longer exists becomes a tombstone in `ui-inventory.md`; its
id is never reused.

Nothing in this section is a golden-master seam. UI stays excluded from the
seam taxonomy (`templates/seams.md`'s "Excluded: UI Automation"), no
`specclaw-bf-replay` verdict reads any field above, and a screenshot is
never compared to anything by any specclaw command. Visual fidelity is
established by a named human signing `ui-review.md` against these recorded,
hashed captures — this manifest exists to make that evidence citable, not
to automate the judgement.

## (g) Canonical field-path language

One syntax, used everywhere a field path is written or computed: a fixture's
`normalized_fields`, `compare.json`'s `field_path`, and every path a report
prints.

```
path     := segment ( "." segment )*
segment  := key index*
index    := "[" ( digits | "*" ) "]"
```

- **Rooted at the `output` object.** `result.credit_note_id` refers to
  `output.result.credit_note_id`. A leading `output.` is *not* canonical; it is
  accepted, stripped, and reported as a canonicalization WARN naming the
  canonical spelling, because it resolves unambiguously.
- **Array indices attach to their key with no separating dot**:
  `cases[0].invoice_id`, never `cases.[0].invoice_id`.
- **`[*]` matches any index**: `cases[*].invoice_id` covers every element.

**Matching semantics, precisely.** A pattern matches a concrete path when,
segment for segment, the pattern is **equal to, or a proper prefix of**, the
concrete path — and each segment matches when its key is string-equal and each
index selector is either numerically equal or `[*]`.

- `result.credit_note_id` matches exactly that scalar.
- `cases[*].invoice_id` matches `cases[0].invoice_id`, `cases[1].invoice_id`, …
- `result.timestamps` (naming an object) matches every path beneath it — prefix
  semantics are how a whole subtree is normalized in one entry.
- A pattern that resolves to **zero** concrete paths is *dead*. Dead paths are a
  hard error at record time (a) and a reported WARN at compare time (j.4).

The resolution primitive is shared, not reimplemented: `specclaw-bf-baseline`
and `specclaw-bf-replay` both call the same jq module
(`$CLAUDE_PLUGIN_ROOT/lib/gm-paths.jq`), so capture-time validation and
compare-time exclusion can never drift into two lookalike implementations that
disagree about what a path means.

## (h) Semantic error identity and the per-project error map

`error_code` (b.1) is the field that makes error comparison survive a rebuild.
Its vocabulary is **per project**, and it lives in the target repo:

```
.specclaw/baseline/error-map.md
```

- **Nothing in this plugin ever contains a code, a framework exception name, or
  a mapping between them.** The plugin ships only the empty document skeleton
  (`templates/error-map.md`).
- `bf-baseline-designer`, in harness mode, **creates or extends** `error-map.md`
  as it encounters legacy error conditions. Each entry cites the **legacy**
  source `file:line` that raises that condition. The document is human-reviewable
  by design: a person can read it and see what each code claims to mean and
  where the claim came from.
- `bf-replay-mapper` maps the rebuild's errors into the **same** vocabulary when
  it writes actual results, citing the **rebuild** source `file:line` for each
  code it uses. It never adds a code that isn't already in `error-map.md`, and
  never renames one.
- **Ask, don't guess.** An error either agent cannot confidently map is *not*
  given a plausible-looking code. The agent raises a typed pending question
  (`templates/pending-questions.md`, triggers T2/T3/T4) and leaves
  `error_code: null` on the affected fixture or actual result. This is the same
  soft-block mechanism every other provisional artifact uses.

**Entry format** — one `###` heading per code, so `record` can verify a code
exists with a literal heading grep, exactly as `sanction-check` verifies a CQ:

```markdown
### <SEMANTIC_CODE>

- **Condition:** <the business condition, in the project's own language>
- **Legacy source:** <path/File.ext:142>
- **Rebuild source:** <path/File.ext:88, or "not yet mapped">
- **Raised as (legacy):** <the raw exception type/message shape, for reference only>
```

**Mechanical checks `specclaw-bf-baseline record` performs** (all from declared
data, none by judgement):

1. Every non-null `error_code` appearing in any fixture has a matching
   `### <CODE>` heading in `error-map.md`. An unmapped code is a hard error.
2. A fixture with `outcome: "REJECTED"` and `error_code: null` is legal **only**
   when its scenario carries the `⚠ PROVISIONAL` marker — i.e. an agent
   genuinely asked instead of guessing. Otherwise it is a hard error naming the
   fixture.

`error-map.md` must travel with the other Phase A artifacts into the rebuild
repo (see `docs/rebuild-workflow.md`'s copy set) — without it the mapper has no
vocabulary to map into.

## (i) Seam layers

Every seam is observed at exactly one layer. The enum is closed:

| `seam_layer` | Observed at |
|---|---|
| `pure-function` | A function/method with no persistence and no clock — called directly. |
| `service` | A service/application-layer entry point, called in-process, with its own arrange step. |
| `http` | The application's HTTP/API surface — request in, response out. |
| `persistence` | The data/ORM boundary — cascade, delete-rule, and constraint behaviour. |

The layer is **declared once and copied thereafter**, never re-derived:

- `seams.md` — each ranked seam declares its layer.
- `scenarios.md` — each `### GM-NNN` block carries `- **Seam layer:** <enum>`.
- `manifest.json` — `record` extracts it verbatim from the scenario block.
  A missing or non-enum value is a hard record error; there is no default.
- `mapping.json` — each entry carries **both**:
  - `legacy_seam_layer` — copied from `selection.json` (which carries the
    manifest's value unchanged). Not re-derived, not re-judged.
  - `replay_seam_layer` — the layer the generated replay test *actually*
    targets.

**The same-layer rule.** A replay test must exercise the rebuild at the layer
the fixture was captured at. A fixture captured at `service` replayed through
`http` is not a weaker proof — it is a different measurement, and its
divergences are noise about transport, serialization, and middleware rather
than about the business rule the fixture pins.

If the equivalent layer genuinely does not exist in the rebuild, that is
`NOT REPLAYABLE` with `category: "seam-mismatch"` and a remediation naming what
would have to exist. **"Test it through HTTP instead, because that's what's
reachable" is never a valid resolution.**

This is enforced mechanically, on the same trust model as `sanction-check`
re-verifying the auditor: `specclaw-bf-replay compare` re-checks every mapping
entry against `selection.json` before diffing anything, and forces the row to
`NOT REPLAYABLE / seam-mismatch` — whatever the agent claimed — when
`replay_seam_layer` is absent, or differs from the authoritative legacy layer,
or when the entry's own `legacy_seam_layer` does not match `selection.json`.

## (j) Divergence classes and the overall verdict

### (j.1) Per-diff `field_class`

Computed by `specclaw-bf-replay compare`, in this order, first match wins:

| Order | `field_class` | When |
|---|---|---|
| 1 | *(excluded)* | The path is matched by a `normalized_fields` pattern (g) — not emitted at all. |
| 2 | `representation` | The path's last segment is one of (b.2)'s four names. |
| 3 | `unmapped-error-code` | The path's last segment is `error_code`, and either side is `null` while that side's `outcome` is `"REJECTED"` — i.e. (h)'s ask-don't-guess case, not a behavioural difference. |
| 4 | `behavioural` | Everything else. |

**Stub taint is not in this table, deliberately.** A fixture verifying a
backlog item that consumed an `ACTIVE` bypass stub (section (m)) carries
`stub_refs` alongside its diffs — it is a statement about what the rebuild was
*standing on* while it was measured, not about what any field *contained*. It
adds no `field_class`, matches no path, and is never consulted here.

### (j.2) Per-row `divergence_class`

The highest-precedence class present among the row's diffs:

`behavioural` > `unmapped-error-code` > `representation`

No diffs at all → `MATCH`. The per-fixture verdict enum is unchanged
(`MATCH` / `DIVERGES` / `ERROR` / `NOT REPLAYABLE`); `divergence_class` rides
alongside it. Everything downstream — whether the auditor is spawned at all,
what `sanction-check` demands a CQ for, what FAILs the run — keys off
`divergence_class == "behavioural"`, so representation noise never reaches an
agent and never demands a product decision.

### (j.3) Overall verdict

Evaluated strictly in this order, by bash, from the counts above:

| # | Condition | Verdict | Exit |
|---|---|---|---|
| 1 | selected > 0 and every selected fixture is NOT REPLAYABLE (seam-mismatch rows included) | `INCOMPLETE` | 2 |
| 2 | any `ERROR`, **or** any unsanctioned `behavioural` divergence | `FAIL` | 1 |
| 3 | any exercised `PROVISIONAL` fixture, **or** any exercised `SUPERSEDED` fixture, **or** any `unmapped-error-code` row | `PASS-PENDING-DECISIONS` | 1 |
| 4 | otherwise | `PASS` | 0 |

Rule 2 preceding rule 3 is the guarantee: **an unsanctioned behavioural
divergence is always FAIL.** No provisional, superseded, or unmapped state ever
converts it into `PASS-PENDING-DECISIONS`. A *sanctioned* behavioural divergence
and a representation-only difference both reach `PASS`.

**Stub taint appears in no row of this table and in no exit code.** A run whose
exercised fixtures rest on an `ACTIVE` stub reaches exactly the verdict it would
have reached without the registry — and then says so, on the verdict line, in
its own report section, and in `run-metadata.json`. Taint marks a PASS as
resting on something unreal; it never converts a FAIL into anything softer, and
there is no fifth verdict and no third exit code. See (m.3).

### (j.4) `compare.json` schema

```jsonc
{
  "compare_schema": 2,
  "plugin_version": "0.9.0",
  "results": [{
    "scenario_id": "GM-019",
    "verdict": "DIVERGES",
    "fixture_status": "VERIFIABLE",
    "stub_refs": ["ST-001"],
    "divergence_class": "behavioural",
    "diffs": [
      {"field_path": "threw", "expected": true, "actual": false,
       "field_class": "behavioural"}
    ],
    "normalization_warnings": [
      {"path": "cases[*].id", "matched": 0,
       "suggestions": ["cases[0].case_id"], "against": "actual"}
    ],
    "legacy_seam_layer": "service",
    "replay_seam_layer": "http"
  }],
  "summary": { "match": 12, "behavioural_sanctioned": 2,
               "behavioural_unsanctioned": 3, "representation": 18,
               "unmapped_error_code": 1, "seam_mismatch": 2,
               "error": 0, "not_replayable": 5 }
}
```

`legacy_seam_layer`/`replay_seam_layer` appear on rows forced to
`seam-mismatch`. `normalization_warnings` never changes a verdict — it reports
a normalization path that resolved against the fixture but resolves against
nothing in the actual output, which is precisely the signal that the rebuild
reshaped the field the path was meant to exclude. `stub_refs` is **carried**
from `selection.json`, never computed here — an empty array (or an absent
field, on a row written by an older specclaw) means untainted.

## (k) Identity and idempotency capture

A generated identifier — an auto-increment key, a UUID, a sequence-derived
document number — proves nothing when compared across two independently seeded
databases. Comparing one is guaranteed noise; the *rule* it was standing in for
goes unverified.

For any scenario whose business rule is about identity or idempotency, capture
the **assertion**, not the value:

```jsonc
"output": {
  "outcome": "OK", "error_code": null, "threw": false,
  "first_call_created": true,
  "second_call_same_entity": true,
  "second_call_created_duplicate": false
}
```

These are booleans the seam itself can answer, they mean the same thing in both
applications, and they fail loudly when the rule is actually broken. Where a raw
generated ID is recorded at all — as evidence, or because it is genuinely part
of the output shape — it belongs in `normalized_fields` via a canonical path (g),
which is what makes it excluded rather than merely hoped-over.

This is guidance for scenario design and harness/test generation. The comparator
needs no special case for it: once (g) makes normalization paths actually
resolve, an ID listed there is genuinely skipped.

## (l) The module hierarchy, and module selection

A **module** (`MOD-NNN`) is a migration and acceptance unit — the "one flow at
a time" slice a large legacy system is rebuilt and behaviourally signed off in.
The hierarchy is:

```
MOD-NNN (module)  →  BL-0NN (backlog item)  →  DR-NNN (rule)  →  GM-NNN (scenario)
```

**Modules never fragment the corpus.** There is one `manifest.json`, one
`decisions.md`, one `rebuild-backlog.md`, one `fixtures/` directory. A module is
a **selection dimension** over that single shared corpus — never a per-module
directory, never a per-module manifest. Splitting the corpus would make a
cross-module flow unrepresentable, which is precisely the thing this hierarchy
exists to keep visible.

### (l.1) Who declares what — one direction per fact

The map is written before any backlog exists, so ownership is declared once, in
exactly one place, and copied thereafter:

| Fact | Declared by | Copied to |
|---|---|---|
| A module's entities, rules, services, screens | `module-map.md` | — |
| A backlog item's module | `rebuild-backlog.md`'s `**Module:**` field | — |
| A scenario's module(s) | `scenarios.md`'s `Modules` field, derived once from the map's rule ownership | `manifest.json`'s `module_ids`, verbatim |

Nothing re-derives a module downstream. `record` does not infer a scenario's
module from its rules; `resolve` does not read `scenarios.md`; no agent computes
module selection or a module verdict. `module-map.md`'s `Backlog items:` field is
a back-filled convenience only — the backlog is authoritative for item
membership.

`record` performs two mechanical checks from declared data: a **hard error** on
a declared `MOD-NNN` with no `### MOD-NNN` heading in `module-map.md` (an
unmapped module tag selects nothing, silently — the same reasoning as (h)'s
unmapped error code), and a **WARN** when a scenario's module disagrees with the
module its own `BL` item is filed under. The warn never blocks the manifest: one
of two analysis documents is wrong, bash cannot know which, and a documentation
disagreement must not cost a capture run its evidence.

### (l.2) Multi-module scenarios and the cross-module honesty rule

A scenario whose pinned rules span modules is tagged with **all** of them. This
is required, not an edge case to round down:

- `specclaw-bf-replay resolve MOD-NNN` selects it for **every** module it names
  (ANY-of), because it is the record of a flow crossing those boundaries.
- The report's module rollup counts it toward **every** module it touches, and
  each module's row states **how many of its fixtures are shared, naming the
  other modules**. A module verdict that silently excluded its shared flows
  would be a false verdict — those are exactly the flows that break when one
  module is rebuilt in isolation.
- A module pulled into a run only because a shared fixture touches it is marked
  `PARTIAL`, with its verdict qualified `(of the selected subset only)`, so a
  glimpse of another module can never read as that module's verdict.
- A module-scoped design merge may not retire a cross-module scenario: it is
  preserved and reported, because a one-module run has no authority over
  another module's coverage.

### (l.3) Selection only

`--module` changes **which** fixtures are compared and **nothing** about what a
comparison means. Field classification (j.1), row class (j.2), the four-step
overall verdict and its exit codes (j.3), the same-layer rule (i), sanctioning,
and evidence retention are all identical across the three selection scopes
(change / module / corpus). The overall verdict is always computed over the whole
selected set; a per-module verdict is a reporting view over the same rows and
gates nothing.

## (m) Module bypass and the stub registry

The module dependency graph (l) is the **recommended** build order, not a lock.
A team can start any module before its dependencies exist — by explicitly
choosing, per unmet dependency, something to stand in for it. That substitution
is called a **bypass**, it is recorded as an `ST-NNN` entry, and everything
built on top of it is marked as such until the real module lands.

The purpose of this section is not to make out-of-order work possible — that
was always possible, by simply doing it. It is to make out-of-order work
**visible**: to guarantee that no report, no module status, and no retained
evidence package can present a verdict earned against a stub as though it were
earned against the real thing.

### (m.1) The registry

```
.specclaw/analysis/module-stubs.md
```

One `### ST-NNN` entry per bypass. The plugin ships only the document skeleton
(`templates/module-stubs.md`), which carries the full entry format; the fields
`specclaw-bf-replay` and `specclaw-bf-rebuild-collect` actually read are:

| Field | Read by | For |
|---|---|---|
| `Status` | replay `resolve`, rebuild-plan `render`, `module-status` | `ACTIVE` taints; `RETIRING`/`RETIRED` do not |
| `Substitutes` | rebuild-plan `render`, `module-status` | which `BL-0##`/`MOD-###` is being stood in for |
| `Strategy` | reporting only | `stub-interface` \| `mock-data` \| `feature-flag` \| `item-split` |
| `Consumed by` | replay `resolve` | the `BL-0##` join key that produces `stub_refs` |
| `Fakes` | reporting only | the one-line human-readable claim, quoted into reports |
| `Mock seed` | replay `resolve` | (m.5) — a WARN source, never an assertion |

**Three properties, each load-bearing:**

- **One shared corpus.** There is one registry, exactly as there is one
  `manifest.json`, one `decisions.md`, one `rebuild-backlog.md`. A stub is not
  a per-module artifact — a bypass is by definition a relationship *between*
  modules, and splitting the registry would make the interesting ones (a stub
  faking MOD-005 for three items in MOD-009) unrepresentable.
- **Append/update-in-place; archive-then-replace does NOT apply.** Same
  invariant as `clarifications.md` and `pending-questions.md`. Retirement
  updates an entry's `Status` and fills its `Retirement` line; nothing ever
  deletes an entry or renumbers an id (c).
- **Absence is a normal state.** No registry means no stubs. Every reader
  treats it as empty, silently — no warning, no degradation, no verdict change.
  A project that never bypasses anything never encounters this section.

### (m.2) Who declares what — one direction per fact

The same discipline as (l.1): declared once, copied thereafter, never
re-derived downstream.

| Fact | Declared by | Copied to |
|---|---|---|
| That a bypass is needed at all | **a human**, at `/specclaw:propose` time | the `ST-NNN` entry |
| Which strategy substitutes the dependency | **a human**, from the four offered | `Strategy` |
| Which items consumed the stub | `/specclaw:propose`, from the item being proposed | `Consumed by` |
| What the stub concretely fakes, and where it lives | the **build agent**, in the rebuild's own stack | `Fakes`, `Implementation` (cited `file:line`) |
| Which fixtures are tainted | **bash**, joining `Consumed by` → each fixture's `bl_items_resolved` (its acceptance-basis-derived BL set, per (b)) | `stub_refs` |
| Whether a module is honestly PASSED | **bash**, from `stub_refs` on the latest run | the module status view |

**A bypass is never agent-decided and never a silent default.** An agent may
detect that a dependency is unmet and must present the options; choosing one is
a human act, recorded with a name and a date. This is the ask-don't-guess rule
(h) applied to dependencies, and it is the reason `Chosen by` is a required
field rather than a courtesy.

**Symmetrically, an agent never computes taint.** `stub_refs`, the per-module
tainted counts, the `PASSED*` rendering, and the retirement block are all bash
joins over declared data — the same trust model that keeps `divergence_class`,
the seam-layer verdict, and `PROVISIONAL` out of agent hands (j).

### (m.3) Taint is a marker, exactly like PROVISIONAL

A fixture is **stub-tainted** when any `BL-0##` in its `bl_items_resolved`
appears in the `Consumed by` field of an `ACTIVE` registry entry. That
produces `stub_refs: ["ST-NNN", ...]` on the fixture, which flows:

```
module-stubs.md  →  selection.json  →  compare.json  →  report + run-metadata.json
   (Consumed by)      (per fixture)      (per row)        (verdict line, section, metadata)
```

Every consequence is a **statement**, never a computation:

- The report's overall verdict line appends `(with active stubs: ST-001, ...)`
  when any *exercised* fixture is tainted. The verdict token itself is
  unchanged and still comes first, so `PASS` stays parseable as `PASS`.
- The report gains a **Stubs In Effect** section: each entry, what it fakes,
  which fixtures it tainted.
- `run-metadata.json` records `stubs_in_effect`, `stub_tainted_items`,
  `stub_tainted`, and `counts.stub_tainted_exercised`.
- A module whose items' latest verdicts include a tainted one renders
  `PASSED* (stubs active: n)` rather than `PASSED`.

**And nothing else.** Verdict computation is byte-identical: taint enters no
condition in (j.3), adds no `field_class` (j.1), adds no `divergence_class`
(j.2), and produces no exit code of its own. It never softens a `FAIL` — a
stub-tainted `FAIL` is reported as `FAIL`, exit 1, with the taint noted
alongside. The relationship to `PROVISIONAL` is instructive but not identical:
`PROVISIONAL` *does* participate in the verdict (rule 3 of (j.3)), because an
open question means nobody has decided what correct is. A stub is different —
the comparison genuinely ran and genuinely matched. What is in question is not
the verdict but its **standing**, and standing is reported, not computed.

### (m.4) Retirement

`ACTIVE` → `RETIRING` → `RETIRED`, and the middle state is not ceremony. With
only two states the run that proves a stub is gone is itself stamped tainted
(the entry is still `ACTIVE` while it runs), so the evidence contradicts what
it demonstrates; flipping to `RETIRED` first means a failing re-replay leaves
an entry falsely marked retired. `RETIRING` is the only state in which a clean
run can honestly retire a stub, and a `RETIRING` entry whose re-replay FAILs
goes back to `ACTIVE` with the failing run id noted.

The trigger for offering retirement is mechanical and narrow: the substituted
`BL-0##` carries a declared `BUILT:` line in its own **Status notes
(human-added)** block in `rebuild-backlog.md`. Prose is not parsed. specclaw
records no built state for a backlog item, and inferring "done last week" from
free text would be precisely the guess this whole mechanism exists to prevent.

### (m.5) What cannot be asserted, stated plainly

A `mock-data` entry may declare a `Mock seed` path. Recording it is useful; it
is **not** a guarantee. No specclaw command observes which data a running
application loaded, so nothing here can assert that a mock seed was inactive
during an acceptance run. The single mechanical use is a **WARN** — never a
failure, never a verdict change — when a `mock-data` entry is `RETIRING` or
`RETIRED` and its declared seed file still exists on disk.

More generally: this section makes a bypass **traceable**, not safe. A tainted
PASS says "the rebuild matched recorded behaviour while standing on something
unreal, and here is exactly what." Whether that is acceptable is a human
judgement about a named, dated, cited decision — which is the most this format
can honestly offer, and considerably more than an untracked stub offers.

### (m.6) `item-split` is not one of these

`item-split` used to be listed here as a fourth strategy. It is not one, and
treating it as one cost a real project an entire layer of a real feature.

The other three **fake a dependency**, which puts the *standing of a verdict* in
question — hence `stub_refs`, hence taint, hence retirement. A split fakes
nothing; it defers real scope, which puts something else entirely in question:
**whether the item is finished**. An `ST-NNN` entry has no field for what was
deferred, which rules each half covers, or what unblocks the remainder — so a
split recorded here lost every fact a resume would later need, while tainting
fixtures that nothing unreal was ever standing on.

Splits now live in section (o). `stub-append --strategy item-split` is refused
by name. Entries recorded before that registry existed keep
`Strategy: item-split` in `module-stubs.md` forever — ids are permanent and
entries are never deleted — and every reader **excludes them from taint and
from the retirement block**, which is what the three documents describing them
always claimed and no code ever implemented.

## (n) The target foundation and `bootstrap-manifest.json`

Every section above describes work done *against* an application. This one
describes the application's own existence.

The pipeline used to have no owner for creating the target application
skeleton. `bf-analyze`/`bf-architecture`/`bf-domain`/`bf-clarify`/`bf-baseline`
are read-only and run in the legacy repo; `bf-rebuild-plan` writes one document
and calls no lifecycle command; `bf-replay` assumes the rebuild's "real
service/entity files" already exist. The only writer of application source was
`/specclaw:build`, which is scoped to one change — so the first backlog item
proposed inherited responsibility for inventing the skeleton, and when that
item's scope was split, an entire layer of it disappeared with no record that
it ever should have been there.

`/specclaw:bf-bootstrap` owns that work, once per rebuild repo, before any
backlog item is developed.

### (n.1) The manifest

```
.specclaw/bootstrap/bootstrap-manifest.json
```

Written by `specclaw-bf-bootstrap record` — bash-derived from the agent's own
declaration, the gate result and the smoke run, never agent-authored.

```jsonc
{
  "bootstrap_schema": 1,
  "plugin_version": "0.13.0",
  "generated": "2026-08-14",
  "generated_at": "2026-08-14T09:12:00Z",
  "project_root": "…",
  "not_applicable": null,
  "foundation_ready": true,
  "stack": { "frontend": "…", "backend": "…", "orm": "…", "database": "…",
             "frontend_test_runner": "…", "backend_test_runner": "…" },
  "decisions_consumed": [
    { "id": "SQ-014", "decision": "…", "source": ".specclaw/analysis/decisions.md" }
  ],
  "pillars": [
    { "id": "frontend-shell", "status": "present", "evidence": "web/src/main.tsx:1" },
    { "id": "cors", "status": "absent-by-decision", "reason": "SQ-003 …" }
  ],
  "files_created": [ { "path": "…", "purpose": "shell" } ],
  "route_census":  [ { "route": "/health", "kind": "health", "file": "…:42" } ],
  "screen_census": [ { "screen": "app shell", "kind": "shell", "file": "…:10" } ],
  "ui_tokens_imported": ["TK-001"],
  "ui_tokens_skipped_reason": null,
  "plan": ".specclaw/bootstrap/bootstrap-plan.md",
  "gate": { "result": "PASS", "checks_run": 7, "checks": [], "problems": [],
            "limits": "…" },
  "smoke": [ { "check": "api-build", "result": "PASS", "required": true,
               "log": ".specclaw/bootstrap/smoke/api-build.log" } ],
  "smoke_summary": { "total": 6, "passed": 5, "failed": 0, "skipped": 1 }
}
```

- `bootstrap_schema` — integer, currently `1`. `foundation-check` refuses a
  manifest that lacks it or carries a different one, naming a re-run as the fix,
  rather than reading unknown fields under assumed defaults. Same reasoning as
  (c')'s manifest floor.
- `stack` — free-form, per project, and **stack-neutral in this document**: the
  keys name roles, the values are whatever the project decided. No framework
  name appears in the plugin, only in a rendered manifest.
- `not_applicable` — `{reason, declared_by}` when a repo has declared once that
  it is not a rebuild target (see (n.5)); `null` otherwise.
- `smoke[].log` is a repo-relative path to a capped log. A `SKIPPED` entry
  carries its reason in `detail`; a skip with no reason is refused at record
  time, because "skipped" without a reason is indistinguishable from "never
  considered".

**New-repo-born, and never copied.** `bootstrap-manifest.json` is created in the
rebuild repo, on exactly the same terms as `module-stubs.md` (m.1) and
`item-splits.md` (o.1): it is not part of the Phase A copy set, nothing copies
it from the legacy repo, and no legacy-repo command reads it.

### (n.2) Bootstrap consumes decided architecture; it never decides architecture

Seven decisions are **required** and have no default anywhere: `SQ-001` (target
platform), `SQ-002` (database engine/hosting), `SQ-003` (hosting model),
`SQ-004` (auth approach), `SQ-006` (UI framework), `SQ-013` (UI fidelity
policy), `SQ-014` (target backend stack).

- A required decision that is neither decided nor declared not-applicable is a
  **hard stop naming the exact id**, before anything is created. This is the
  ask-don't-guess rule (h) applied to scaffolding, and it is stricter than
  (h)'s soft-block on purpose: a pending question leaves one fixture
  provisional, whereas a guessed stack is inherited by every backlog item built
  on top of it and cannot be corrected without discarding the work.
- **"Not applicable" is an answer**, and it lives in exactly one place:
  `clarifications.md`'s own `## Not Applicable` section. A rebuild with no
  server side has no backend stack to choose, and demanding one would be
  demanding a decision that does not exist.
- A decision is read **heading-anchored** — a decided `### SQ-0NN —` block with
  a non-empty `- **Decision:**` line. Headings appear only under
  `## Decisions`, never under `## Outstanding Questions` (which lists open ids
  as plain bullets), so this cannot mistake an open question for a decided one.
  The same single-grep proof `sanction-check` rests on.
- An **accepted** ADR in the rebuild repo is a legitimate source. A `proposed`
  one is context, never an answer. `record` verifies that every cited source
  file exists and greps it for the id; where it cannot confirm the citation it
  emits a `WARN` naming it rather than passing silently. Bash cannot judge
  whether an ADR is accepted in whatever format a repo writes ADRs in, and it
  says so instead of pretending.

### (n.3) Pillars, and who computes readiness

A **pillar** is a role the foundation plays. The enum is closed and names no
technology, on the same terms as (i)'s seam layers:

`frontend-shell` · `frontend-routing` · `api-client` · `backend-solution` ·
`di` · `config` · `cors` · `error-handling` · `persistence` · `migrations` ·
`health-check` · `test-frontend` · `test-backend` · `theme-plumbing`

Each is `present` | `absent-by-decision` | `failed`, and **anything other than
`present` carries a stated reason**. An absent pillar is either decided away,
with the decision named, or it is a failure — never a silent skip, which is how
a half-built foundation reads as a finished one.

`foundation_ready` is computed by `record`, from declared data, and is **never
agent-asserted**: every pillar `present` or `absent-by-decision`, every
*required* smoke check `PASS` or `SKIPPED` with a reason, `gate.result == PASS`,
and every required decision recorded as consumed with a source path that
exists. `record` is fallible by design on the same terms as
`specclaw-bf-baseline record`: it collects every problem in one pass and, if
there are any, writes no manifest **and archives nothing** — a run that
produced an invalid state must not also destroy the last valid one.

### (n.4) The foundation-only gate, and exactly what it cannot prove

`specclaw-bf-bootstrap gate` checks the agent's declared census against the
closed vocabularies plus narrow id greps:

1. Every pillar id and status is in its enum, and every non-`present` pillar
   states a reason.
2. No file is declared with purpose `capability`. The purpose exists in the
   vocabulary **solely so the gate can name what it is rejecting**.
3. Every file purpose is in the closed set (`shell`, `routing`, `api-client`,
   `di`, `config`, `cors`, `error-handling`, `persistence`, `migrations`,
   `health`, `test-harness`, `theme`, `build`, `docs`).
4. At most one `health` route; every other route and every screen is
   `shell`/`error`/`layout`.
5. No created file cites a `DR-###`, `BL-###` or `SCR-###` id.
6. Only the `TK-` groups the declaration says it imported appear in the
   scaffold.
7. Every declared smoke check id is in the closed set.

**What this gate cannot prove, stated plainly.** It is a declared-census check
plus id greps. **A business rule implemented without citing its `DR-###`
passes it.** Nothing here reads the scaffold's logic, and nothing here could:
doing so would require judging, per stack, whether a given function encodes a
domain rule — which is exactly the kind of judgement this plugin keeps out of
bash and out of agents' verdicts alike.

What it does buy is real and worth having: a scaffold that names a specific
rule, backlog item or legacy screen is unambiguously over the line and is
caught; a capability file cannot be declared without rejection; and the census
itself makes the boundary claim **reviewable by a human** rather than merely
asserted. A gate that overclaimed here would be worse than no gate, because
the report would read as proof.

### (n.5) The propose gate

`/specclaw:propose` reads `specclaw-bf-bootstrap foundation-check` before it
creates anything, and stops when the foundation is not ready — naming the
command that fixes it, the same UX every other precondition gate in the
pipeline uses.

- **Inert by default.** No `rebuild-backlog.md` means `applicable: false`, and
  propose behaves exactly as it always has. A greenfield project never sees
  this, on the same terms as `bypass-check` (m).
- **Fails closed.** A manifest that cannot be parsed, carries an unknown
  schema, or claims `foundation_ready` while recording a failed smoke check
  (a combination `record` never writes, so the file has been hand-edited) all
  report not-ready with the reason. Passing a gate on a file nobody could read
  would defeat its purpose.
- **The legacy-repo escape hatch is a declaration, not an inference.** A legacy
  repo carries a `rebuild-backlog.md` too, so the gate would fire there. Rather
  than guessing which repo it is in — there is no honest signal for that —
  `specclaw-bf-bootstrap not-applicable` records the answer once, with a
  reason and a named human, and the gate passes on that declaration
  thereafter. `--declared-by` is required for the same reason `Chosen by` is
  (m.2): a declaration that switches off a gate is attributable or it is
  malformed.

### (n.6) The token-plumbing line

Where the foundation stops and the UI-fidelity workstream (f) begins:

- Foundation **may** create the theme *mechanism* and import the values of
  `TK-` groups whose scope is **`global`**. `bf-rebuild-plan` already unions
  the global groups into *every* screen-bearing item's `**UI fidelity:**`
  line, which makes them a shared prerequisite of all of them — and a shared
  prerequisite no single item can own is what foundation means.
- Foundation **may not** import a `TK-` group scoped to a specific `SCR-###`,
  and **may not** reproduce any screen's layout structure, even under
  `FAITHFUL`. Those are exactly what a named human signs in `ui-review.md`,
  per change, per screen.
- **No contract in (f) changes.** The foundation *claims* a global token's
  value; a human still *confirms* it in the first screen-bearing change's
  review. No `ui-review.md` row is skipped, and no `SCR-###` coverage
  obligation moves, because bootstrap ran.
- Under `REINTERPRET`, an undecided `SQ-013`, or a decided policy whose
  `.specclaw/ui/` artifacts are absent: the mechanism only, no values, and
  `ui_tokens_skipped_reason` records why. A stated degradation, never a silent
  one — the same discipline `bf-rebuild-plan` applies when it holds
  screen-bearing items at `OPEN QUESTIONS` rather than quietly dropping a UI
  requirement.

## (o) Item splits and the `IS-NNN` registry

An **item split** is the dependency-bypass option that fakes nothing. Part of a
backlog item is implemented now; the rest is deliberately deferred until the
items it depends on exist.

The purpose of this section is the same as (m)'s and reached by a different
route. (m) exists so that no verdict earned against a stub can present as one
earned against the real thing. **This one exists so that no backlog item can
present as finished while a layer of it is missing** — and so that, weeks or
months later, specclaw still knows exactly what was completed and what remains.

### (o.1) The registry

```
.specclaw/analysis/item-splits.md
```

One `### IS-NNN` entry per split. The plugin ships only the document skeleton
(`templates/item-splits.md`), which carries the full entry format; the fields
bash actually reads are:

| Field | Read by | For |
|---|---|---|
| `Status` | propose, rebuild-plan `render`, replay `resolve` | `ACTIVE`/`READY-TO-RESUME` mean the item is unfinished; `COMPLETE` is history |
| `Item` | all of them | the `BL-0##` this split is about |
| `Rules implemented` / `Rules deferred` | replay `resolve` | the partition that says which fixtures cover built vs deferred scope |
| `Blocked until` | rebuild-plan `render`, propose | the `BL-0##` set whose declared `BUILT:` notes compute `READY-TO-RESUME` |
| `Layers deferred` | `split-append` | the layer-removal guard (o.2) |
| `Deferred` | reporting only | the human-readable claim, quoted into markers and reports |
| `Change` / `Evidence` / `Replay evidence` | propose | what a resume cites instead of rebuilding |

**The same three properties as (m.1), each load-bearing:** one shared registry;
append/update-in-place with archive-then-replace explicitly not applying; and
**absence is a normal state** — no registry means no splits, silently, with no
warning, no degradation and no verdict change.

### (o.2) Two guards against a split silently widening

**The split the human chose is the split that happens.** `split-append`
enforces that with two refusals, because prose in a proposal is not something a
later command can check.

1. **The DR partition.** `Rules implemented` and `Rules deferred` must together
   account for **every** `DR-###` in the item's own acceptance basis, with no
   overlap and nothing left out. A rule in neither half is scope belonging to
   nobody, so nothing downstream can tell whether it shipped. This is also what
   makes (o.4) possible without an agent reading prose at run time.
2. **Layer removal.** A split that defers the whole `ui` layer from a
   **screen-bearing** item is refused unless
   `Layer removal confirmed by` names a human. Screen-bearing is itself
   declared data — the item's own `SCR-###` citations or its rendered
   `**UI fidelity:**` line — never inferred from a title.

**The honest limit, stated as plainly as (m.5)'s.** Bash can *require* the
attestation; it cannot verify that a human typed it. That is the same trust
model `Chosen by` has always run on. What the refusal buys is that the
confirmation cannot be skipped silently and that the record names who gave it.

### (o.3) The state model, and who flips each transition

```
ACTIVE  →  READY-TO-RESUME  →  COMPLETE
```

| Transition | Actor | Basis |
|---|---|---|
| → `ACTIVE` | `/specclaw:propose` | the human's own choice, with their name |
| `ACTIVE` → `READY-TO-RESUME` | **bash**, in `bf-rebuild-plan --refresh` | every `Blocked until` id carries a declared `BUILT:` note |
| `READY-TO-RESUME` → `COMPLETE` | **Claude**, only on a clean `--item` run | that run's id, cited |

`READY-TO-RESUME` is computed and **written** by bash — the single-line `Status`
rewrite, one direction only, never back, no other field touched. This is the one
place a rendering command writes into a registry, and it is deliberate: the
transition is a *pure function of declared data*, so there is no human judgement
to defer to, and leaving it to a manual flip would make a stale `ACTIVE`
indistinguishable from "nobody got round to it" — which is exactly the ambiguity
a resume cannot afford. (`bf-clarify render` already performs the same surgical
single-line `Status` rewrite when it promotes a pending question.)

`COMPLETE` is a handoff instead, on the same terms as `RETIRED` (m.4): it
requires an act in the world — the deferred work actually built and proven — and
bash cannot observe that. `split-update` **refuses `COMPLETE` straight from
`ACTIVE`**, because `ACTIVE` means the deferred scope's own blockers are not all
built, so the work cannot honestly have been done against them.

The governing rule, stated once: **bash writes what bash can prove; a named
actor writes what requires an act in the world.**

It is deliberately not called "retired". Nothing fake ever existed.

A deferral **withdrawn** from the product rather than built is handled manually
and on purpose: strike the deferred scope in `rebuild-backlog.md` and record the
withdrawal in the entry's `Completion` field. There is no automatic path,
because every automatic path would also be a path that marks unbuilt scope done.

### (o.4) A split is never taint, and never a verdict

A split changes **no** verdict, no `divergence_class`, no `field_class`, no
fixture status and no exit code. It adds no `stub_refs` and appears in no row of
(j.3)'s table. Nothing was faked, so nothing's standing is in question.

What it changes is a **statement about completeness**, in three places:

- `rebuild-backlog.md` renders the item `⚠ PARTIALLY BUILT — IS-NNN: deferred
  <scope>`, recomputed from the registry every run and cleared by regeneration
  when the entry reaches `COMPLETE` — the same tier as `⚠ PROVISIONAL` and
  `⚠ STUB-BACKED`, never hand-edited.
- `/specclaw:bf-replay --item BL-###` appends `(partial — split IS-NNN: N of M
  fixtures pin deferred rules)` **after** the verdict token, so `PASS` still
  parses as `PASS`, and states on the report's face that this is **not the
  item's final acceptance**. The partition (o.2) is what lets it name which
  fixtures those are.
- `module-status.md` counts each module's partially-built items.

**Deferred-scope fixtures are reported, never excluded.** A fixture pinning a
deferred rule still runs and still counts. Silently dropping it from the
exercised set would change what a run FAILs on, which is the one thing a
completeness marker must not do — and it would hide a real regression behind a
scope note. The report says instead that N selected fixtures pin rules the split
declared deferred: a FAIL among them is explained rather than mysterious, and a
**PASS among them is a surprise worth investigating** — it means either the
deferred scope was quietly built after all, or the partition is wrong.

### (o.5) What a split can never claim

An `IS-NNN` makes a deferral **traceable**, not harmless. The item is
unfinished; the backlog says so on its face; every `--item` replay of it reports
PARTIAL until the remainder lands. Whether shipping the slice is worth the
incompleteness is a human judgement about a named, dated, recorded decision —
considerably more than an unrecorded split offers, because an unrecorded split
is indistinguishable from a finished item.

## (p) The redesign prototype and `prototype-manifest.json`

Applies only to a rebuild whose `SQ-013` is decided `REINTERPRET`. Under every
other policy — `FAITHFUL`, `THEME-ONLY`, undecided, or not applicable — nothing
in this section exists, no file below is created, and every command behaves
exactly as it does in a project that never had this stage.

### (p.1) What the stage owns, and what it does not

specclaw contains **no UI generator**. `/specclaw:bf-prototype` produces a
brief and hands it to the prototype/UI skill named in `config.yaml`'s
`prototype.skill`. What specclaw owns is the record and the gate: the
legacy-screen to prototype-screen map, the permanent `PS-###` ids, the
questions a redesign raises, the approval join, the bash-computed readiness,
and the tamper-evident manifest.

The prototype is **design-acceptance code and is thrown away.** It is built in
the real decided stack so the client approves realistic component behaviour and
the production team can read it as a reference; that does not make it
production code. It is never copied to the new repo, never a
`/specclaw:bf-bootstrap` input, and `--adopt` refuses a tree whose hash equals
the recorded `tree_hash`. The production foundation comes only from bootstrap's
own scaffold.

### (p.2) The stack is resolved, never chosen

Two values are resolved from the decision record before anything runs: the
frontend **framework** and the frontend **language**. Each is recorded with the
id that sanctions it, who decided it, and when. If either cannot be resolved
with a citation, the command stops naming exactly which one and the route that
answers it.

**The language is never defaulted** — not from the framework's convention, not
from the legacy app, not from anything. A framework name decides a framework
and nothing else. `SQ-006` asks the framework; `SQ-015` asks the language; one
answer written as the framework followed by the language in parentheses, the
language a single bare word, decides both under that single citation.

The resolver is **stack-blind**: it holds no list of frameworks and no list of
languages, and infers neither from the other. It extracts the strings the
decision record contains, keyed on the role of a question and the literal
structure of the documents. Two sources disagreeing is a hard stop naming both,
never a pick — two records of one decision cannot both be right, and choosing
between them would be the tool deciding the stack.

### (p.3) Who writes what

| File | Written by | Regenerated | Copied to the new repo |
|---|---|---|---|
| `prototype-brief.md` | agent | fully, each run | no |
| `app/` (`prototype.output_dir`) | the configured skill, or a human under `--brief-only` | — | **never** |
| `id-registry.json` | bash | append-only | no |
| `prototype-map.md` | bash rows + agent narration | fully, each run | yes, after READY |
| `screens/PS-###.png` | **human** | — | yes, with the manifest |
| `prototype-approvals.md` | **human** | never | no |
| `prototype-manifest.json` | bash (`--record`) | fully, each run | yes, with `screens/` |

`prototype-approvals.md` is **never written by any agent or script.** An
approval is a named person's statement about a design; a record a tool can
write is not one. The same rule that keeps `screens/` human-captured keeps this
file human-authored.

`PS-###` ids are permanent, exactly like `DR-NNN`/`BL-NNN`/`GM-NNN`/`CQ-NNN`.
The registry maps an allocation key — the `SCR-###` a screen replaces, or
`CQ-###:<slug>` for a new screen the CQ sanctions — to its id, and is
append-only. A screen that leaves the inventory keeps its id and renders
`RETIRED`; its number is never reused.

### (p.4) Behaviour changes are questions, not design choices

Anything the redesign would change about what the system **does** — a required
field removed or added, a validation altered, a workflow merged or split, a
status transition changed, a screen retired — is raised as a `PQ-###` in
`pending-questions.md`, tagged `Source: bf-prototype`, citing the `PS-###`, the
`SCR-###` and every affected `DR-###`. `/specclaw:bf-prototype` never allocates
a `CQ` number; `/specclaw:bf-clarify` promotes the question and a human decides
it.

Until it is decided, bash refuses to compute the affected screen `APPROVED`, so
the prototype cannot reach READY with an undecided behaviour change. **That
refusal is the point of the stage.** Without it, a redesign changes what the
system does, a client approves the screen it appears on, and the change arrives
in the rebuild sanctioned by an approval nobody realised they were giving.

Once decided, the change surfaces in `/specclaw:bf-replay` as
`DIVERGES — SANCTIONED (CQ-###)` through the existing sanction path. No replay
logic changes.

### (p.5) Status is computed, never asserted

Per screen, first match wins:

| | Condition | Status |
|---|---|---|
| 1 | an unresolved `PQ`/`CQ` is referenced | `PROVISIONAL` |
| 2 | `APPROVED` and `approved_source_hash` differs from the current `tree_hash` | `STALE` |
| 3 | `CHANGES-REQUESTED` | `CHANGES-REQUESTED` |
| 4 | `REJECTED` | `REJECTED` |
| 5 | `APPROVED` and the hash matches | `APPROVED` |
| 6 | a screenshot exists, no approval row | `IN-REVIEW` |
| 7 | otherwise | `DRAFT` |
| — | in the registry, no longer briefed | `RETIRED` (informational) |

Rule 1 outranking rule 5 is deliberate: an undecided behaviour question means
nobody has agreed to the change, whoever signed the screen off. Rule 2 binds an
approval to the exact tree the approver reviewed — `approved_source_hash` is the
`tree_hash` printed by the `--record` run they looked at — so editing the
prototype afterwards invalidates the approval rather than leaving a stale
signature standing. Rule 4 is reached only when rule 2 cannot fire, so a
rejected screen whose tree then changed stays `REJECTED`.

The agent narrates these; it never infers one, never upgrades one, and never
states a readiness the raw `PROTOTYPE:` line did not print.

### (p.6) Readiness is measured against the backlog

`prototype_ready` is true when every `SCR-###` rendered by an in-scope, active,
screen-bearing backlog item is covered by at least one `APPROVED` screen — or is
retired by a **decided** `CQ`, or recorded out of scope by the backlog — with
none of those screens `STALE` or `PROVISIONAL`, and the recorded framework and
language each still equal what the resolver returns from the current decision
record.

Measuring against the backlog rather than the legacy inventory is what makes
the gate satisfiable. A rebuild deliberately leaves screens behind; a gate that
demanded an approved prototype for every legacy screen would be unmeetable on
every real project and would simply be switched off, which is worse than not
having it. Out-of-scope screens are **listed**, with their reason, rather than
dropped silently.

An **undecided** `CQ` retires nothing. A screen dropped on an unanswered
question is exactly the silent scope cut this stage exists to surface.

### (p.7) The new-repo gates, and what they cannot prove

Under `REINTERPRET`, read from the copied `decisions.md`:

- **`/specclaw:bf-bootstrap`** gains an eighth precondition beside its seven
  decisions: the manifest present and parseable, `screens/` present with every
  screenshot hash re-verified, `prototype_ready: true`, and the manifest's
  `sq013`, framework and language all still consistent with this repo's own
  decision record. Otherwise it scaffolds nothing. This applies to every
  bootstrap mode including `--adopt`.
- **`/specclaw:propose`** applies the same whole-prototype check — so a repo
  bootstrapped before an approval was withdrawn stops for *every* item, not
  only screen-bearing ones — plus a per-item check that every `SCR-###` the
  item references maps to an `APPROVED` screen.

Both fail **closed**: a manifest that cannot be read, cannot be parsed, or
whose screenshots do not verify is reported not-ready with the reason, never
treated as absent and never waved through. Greenfield projects and
non-`REINTERPRET` rebuilds never see either check.

What these gates cannot prove, stated rather than implied: that the prototype
the client approved is a good design, that the approver understood what they
were approving, or that the built application resembles the approved screens.
The first two are human judgements. The third is what
`/specclaw:bf-ui --checklist` asks a human to confirm, row by row, against the
approved screenshot — and it remains a human signature, never a computed
verdict, exactly as UI fidelity does under every other policy.
