#!/usr/bin/env bash
# Fail on shellcheck findings that are not in the baseline.
#
# The previous CI step ran `shellcheck ... || true`, so the job reported success
# no matter what shellcheck said — a green check was not evidence of a clean
# lint. That let 22 real new findings through unnoticed. This gate compares the
# current finding set against plugins/specclaw/tests/shellcheck-baseline.txt and
# fails on anything new.
#
# Findings are compared as `<path> <SCxxxx>` pairs, not line numbers, so moving
# code around does not manufacture "new" findings.
#
# Exit codes: 0 = no new findings (or shellcheck unavailable), 1 = new findings.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
baseline="${script_dir}/shellcheck-baseline.txt"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not installed — skipping the gate (install it to run this locally)" >&2
  exit 0
fi

[[ -f "$baseline" ]] || { echo "baseline not found at $baseline" >&2; exit 1; }

cd "$repo_root" || exit 1

# `-f gcc` gives one finding per line as `path:line:col: severity: msg [SCxxxx]`,
# which normalises to a pair with a single sed. shellcheck exits non-zero when it
# finds anything, so `|| true` here is about *its* exit code, not the gate's.
current="$(mktemp)"
expected="$(mktemp)"
trap 'rm -f "$current" "$expected"' EXIT

# LC_ALL=C on both sides: `comm` needs identical collation, and the default
# locale sorts hyphens inconsistently across environments.
# bin/ also holds .cmd shims so the auth commands are runnable from PowerShell.
# They are batch files, not shell scripts: shellcheck has no shebang to work from
# and reports SC2148 on them. Select only the extensionless files, which is every
# shell script in the directory.
mapfile -t sh_scripts < <(find plugins/specclaw/bin -maxdepth 1 -type f ! -name '*.*' | LC_ALL=C sort)
if [[ ${#sh_scripts[@]} -eq 0 ]]; then
  echo "no shell scripts found under plugins/specclaw/bin" >&2; exit 1
fi

shellcheck -f gcc "${sh_scripts[@]}" 2>/dev/null |
  sed -nE 's/^([^:]+):[0-9]+:[0-9]+: [a-z]+: .*\[(SC[0-9]+)\]$/\1 \2/p' |
  LC_ALL=C sort -u > "$current" || true

grep -vE '^[[:space:]]*(#|$)' "$baseline" | LC_ALL=C sort -u > "$expected"

# comm must read in the same collation the files were sorted in. Without
# LC_ALL=C here it applies the ambient locale, where `specclaw-verify SC2034`
# and `specclaw-verify-context SC2016` order differently than under C — and a
# mis-collated comm reports the same pair as both fixed and new.
new_findings="$(LC_ALL=C comm -13 "$expected" "$current")"
fixed_findings="$(LC_ALL=C comm -23 "$expected" "$current")"

if [[ -n "$fixed_findings" ]]; then
  echo "These baseline entries no longer occur — prune them from shellcheck-baseline.txt:"
  echo "$fixed_findings" | sed 's/^/  /'
  echo
fi

if [[ -n "$new_findings" ]]; then
  echo "::error::shellcheck found new findings not present in the baseline:"
  echo "$new_findings" | sed 's/^/  /'
  echo
  echo "Fix them, or add a targeted '# shellcheck disable=SCxxxx' with a rationale."
  echo "Full shellcheck output follows:"
  shellcheck "${sh_scripts[@]}" || true
  exit 1
fi

echo "shellcheck: no new findings ($(wc -l < "$current" | tr -d ' ') known, all in the baseline)"
