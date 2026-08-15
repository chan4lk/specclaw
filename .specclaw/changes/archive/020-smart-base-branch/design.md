# Design: Smart Base Branch Detection

**Change:** smart-base-branch
**Created:** 2026-07-16

## Technical Approach

Duplicate one small pure-bash helper into both scripts (repo convention: every bin script is self-contained; `yaml_val` is already duplicated the same way):

```bash
# Resolve the base branch: config override > origin/HEAD > gh default > main/master.
detect_base_branch() {
  local cfg
  cfg="$(yaml_val "$CONFIG_FILE" "git.base_branch" 2>/dev/null)"
  if [[ -n "$cfg" ]]; then echo "$cfg"; return; fi
  local head_ref
  head_ref="$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null)"
  if [[ -z "$head_ref" || "$head_ref" == "origin/HEAD" ]]; then
    git remote set-head origin --auto >/dev/null 2>&1
    head_ref="$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null)"
  fi
  if [[ -n "$head_ref" && "$head_ref" != "origin/HEAD" ]]; then echo "${head_ref#origin/}"; return; fi
  if command -v gh >/dev/null 2>&1; then
    local gh_def
    gh_def="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)"
    if [[ -n "$gh_def" ]]; then echo "$gh_def"; return; fi
  fi
  if git rev-parse --verify -q main >/dev/null 2>&1; then echo "main"
  elif git rev-parse --verify -q master >/dev/null 2>&1; then echo "master"
  else echo "main"; fi
}
```

Call sites:
- `specclaw-build setup` — before branch creation: `BASE="$(detect_base_branch)"`; `git fetch origin "$BASE"` (warn-only); start point = `origin/$BASE` if that ref verifies, else local `$BASE`, else HEAD + warning. Divergence warning when `git rev-parse HEAD != git rev-parse <start-point>` and current branch name != base.
- `specclaw-build finalize` — replace the main/master guess with the helper; `git checkout "$BASE"` before merge.
- `specclaw-pr` — replace both the version-check's inline detection and the hardcoded `--base main` with the helper's value.

## Architecture

No new files. Data flow: config.yaml (`git.base_branch`) → detect_base_branch() → {setup start-point, finalize merge target, pr --base}.

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-build` | modify | Helper + setup start-point/divergence warning + finalize merge target |
| `plugins/specclaw/bin/specclaw-pr` | modify | Helper; `--base` from detection; version-check reuses it |
| `plugins/specclaw/templates/config.yaml` | modify | `git.base_branch` commented key |
| `plugins/specclaw/tests/run-parser-tests.sh` | modify | Case 7: fixture bare-origin repo, detection chain + setup start-point asserts |
| `README.md`, `CHANGELOG.md`, version files | modify | FR7 |

## Data Model Changes

`git.base_branch` config key (string, default empty = auto). Additive.

## API Changes

None externally; `specclaw-build setup` JSON gains `"base_branch"` field (additive, informational).

## Key Decisions

1. **Duplicate helper over shared lib** — matches the repo's self-contained-script convention (`yaml_val` precedent); no sourcing infrastructure introduced.
2. **origin/HEAD before gh** — pure-git answer preferred; gh is an optional dependency and may be unauthenticated.
3. **Warn-don't-block** — fetch failures and divergence produce warnings; the operator may be intentionally offline or stacking.
4. **Fork support deferred** — orthogonal concern (remote selection), kept out to hold risk down.

## Grounding sources

- `plugins/specclaw/bin/specclaw-pr` — existing detection to consolidate: `base_branch="$(git -C "$project_root" rev-parse --abbrev-ref origin/HEAD ...)"` vs the hardcoded `gh pr create --base main`.
- `plugins/specclaw/bin/specclaw-build` — finalize's guess to replace: `main_branch="main"` / fallback `"master"`.
- `CHANGELOG.md` 0.3.1 — `yaml_val` duplication precedent across "all 9 scripts".

## Risks & Mitigations

- **Behavior change on non-main repos** → that's the feature; NFR1 pins main-repo behavior; fixture test asserts both worlds.
- **origin/HEAD stale after default-branch rename** → `set-head --auto` self-heal; config override as escape hatch.
- **Quoting bugs with slashed branch names** → AC edge case; quotes everywhere; test uses `release/1.0`-style override assert.
