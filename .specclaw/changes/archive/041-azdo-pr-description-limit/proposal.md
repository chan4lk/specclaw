# Proposal: Keep Azure DevOps PR descriptions under the 4,000-character limit

**Created:** 2026-09-27
**Status:** 🟡 Draft

## Problem

`/specclaw:pr-azdo` builds the PR description by concatenating sections from the change's own artifacts: Summary (the proposal's Problem + Proposed Solution sections, 10 lines each), up to 40 lines of spec acceptance criteria, the first 20 lines of `verify-report.md`, up to 10 test lines, 20 lines of `staged-files-report.md`, and the time-accounting block. `build_pr_description()` in `plugins/specclaw/bin/specclaw-azdo-pr` caps line counts but never characters. On any real change the sum routinely exceeds Azure DevOps' hard **4,000-character** limit on `description`, and the `POST .../pullrequests` call is rejected outright. By then the branch is pushed and every gate has passed, so the lifecycle fails at its last step and the operator has to open the PR by hand.

The title already gets this treatment (the 128-char cap at line 244). The description does not.

## Proposed Solution

Enforce a character budget in `build_pr_description()` before the payload is built, with a *priority-ordered* degradation rather than a blind tail cut:

1. Build every section as it is built today.
2. If the total is ≤ the budget (default **3,900**, which leaves headroom for the footer and for multi-byte/UTF-16 counting drift), send it unchanged. No behaviour change for small PRs.
3. Otherwise, shrink the lowest-value sections first, in a fixed order: time accounting → staged files → verify excerpt → test lines → acceptance criteria → summary. Each section is truncated at a line boundary and ends with a `_…truncated — full text in .specclaw/changes/<change>/<file>_` pointer, so the reader always knows where the rest is. A section that can't fit even its heading plus pointer is dropped and replaced by the pointer line alone.
4. **The verdict line and the footer are never truncated.** A PR that no longer says whether verify passed is worse than a short one.
5. A final hard cap guarantees the output fits, even if every section above still overshoots (e.g. a single enormous line). If that cap fires, the script prints a warning to stderr.

The budget is a named constant, `AZDO_DESC_MAX`, overridable through config (`azdo.pr.description_max`) in case Microsoft changes the limit or an org wants a shorter description.

## Scope

### In Scope
- A character budget and priority-ordered truncation in `build_pr_description()` (`specclaw-azdo-pr`).
- Truncation pointers into the change dir for every section that was cut.
- An optional `azdo.pr.description_max` config key (commented in the config template).
- A test script that builds a description from oversized fixture artifacts and asserts: length ≤ budget, verdict line present, footer present, pointers present, and small inputs are byte-identical to today's output.
- Patch version bump (plugin.json + marketplace.json).

### Out of Scope
- The GitHub path (`specclaw-pr`): GitHub's body limit is 65,536 chars, and nothing has hit it. It can come later if it ever does.
- Updating (PATCHing) descriptions on existing PRs. `specclaw-azdo-pr` only creates PRs.
- Changing *which* sections go into the description, or their line caps.
- Posting the full, untruncated text as a PR comment (see Open Questions).

## Impact

- **Size:** bounded. This alters one function in an existing flow, `specclaw-azdo-pr`'s `build_pr_description`.
- **Files affected:** 3–4 (estimated): `bin/specclaw-azdo-pr`, config template, a new `tests/run-azdo-pr-description-tests.sh`, and the version files.
- **Complexity:** small
- **Risk:** low. Output is unchanged below the budget, and above it the change turns a guaranteed API rejection into a shorter PR.

## Open Questions

- Should the full untruncated description also go up as a PR thread comment after creation, since ADO comments allow far more text? It costs one extra API call, and a comment failure must not fail the PR. Proposed: not in this change.
- Does ADO count the limit in UTF-16 code units or in characters? The 100-char headroom covers typical emoji/non-ASCII content. Measuring with `wc -m` under a UTF-8 locale is proposed.
