#!/usr/bin/env bash
# azdo-pr.sh — Create an Azure DevOps PR for a specclaw change
# Mirrors pr.sh but targets ADO Repos via REST API instead of GitHub.
# Usage: azdo-pr.sh <specclaw_dir> <change_name>
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: azdo-pr.sh <specclaw_dir> <change_name>

Create an Azure DevOps pull request for a specclaw change. Requires:
  - verify-report.md (build + verify must have completed)
  - test policy configured (prompts on first run, enforced on all runs)
  - Azure DevOps auth configured (run: specclaw auth azdo)

Arguments:
  specclaw_dir   Path to the .specclaw directory
  change_name    Name of the change
EOF
  exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

if [[ $# -lt 2 ]]; then
  echo "ERROR: Expected 2 arguments: <specclaw_dir> <change_name>" >&2
  exit 1
fi

SPECCLAW_DIR="$1"
CHANGE_NAME="$2"
CONFIG_FILE="$SPECCLAW_DIR/config.yaml"
AUTH_FILE="$SPECCLAW_DIR/.env"
CHANGE_DIR="$SPECCLAW_DIR/changes/$CHANGE_NAME"

[[ -d "$SPECCLAW_DIR" ]] || { echo "ERROR: specclaw directory not found: $SPECCLAW_DIR" >&2; exit 1; }
[[ -d "$CHANGE_DIR" ]]   || { echo "ERROR: change directory not found: $CHANGE_DIR" >&2; exit 1; }

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

FAILURES=()
fail() { FAILURES+=("$1"); }

# ─── Load Auth ────────────────────────────────────────────────────────────────

# shellcheck disable=SC1090
[[ -f "$AUTH_FILE" ]] && source "$AUTH_FILE"

AZDO_TOKEN="${AZDO_TOKEN:-}"
AZDO_ORG="${AZDO_ORG:-}"
AZDO_PROJECT="${AZDO_PROJECT:-}"
AZDO_REPO="${AZDO_REPO:-}"

# ─── Helpers ──────────────────────────────────────────────────────────────────

yaml_val() {
  local file="$1" key="$2"
  local section field
  if [[ "$key" == *.* ]]; then
    section="${key%%.*}"; field="${key#*.}"
  else
    section=""; field="$key"
  fi
  local in_section=false value=""
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    if [[ -z "$section" ]]; then
      if [[ "$line" =~ ^${field}:[[:space:]]*(.*) ]]; then value="${BASH_REMATCH[1]}"; break; fi
    else
      if [[ "$line" =~ ^[a-zA-Z_] ]]; then
        [[ "$line" =~ ^${section}: ]] && in_section=true || in_section=false; continue
      fi
      if $in_section && [[ "$line" =~ ^[[:space:]]+${field}:[[:space:]]*(.*) ]]; then
        value="${BASH_REMATCH[1]}"; break
      fi
    fi
  done < "$file"
  value="${value#\"}"; value="${value%\"}"; value="${value#\'}"; value="${value%\'}"
  echo "$value"
}

# Fall back to config.yaml values if env vars not set
if [[ -z "$AZDO_ORG" && -f "$CONFIG_FILE" ]]; then
  AZDO_ORG="$(yaml_val "$CONFIG_FILE" "azdo.org")"
  AZDO_PROJECT="$(yaml_val "$CONFIG_FILE" "azdo.project")"
  AZDO_REPO="$(yaml_val "$CONFIG_FILE" "azdo.repo")"
fi

[[ -n "$AZDO_TOKEN" ]]   || die "AZDO_TOKEN not set — run: specclaw auth azdo"
[[ -n "$AZDO_ORG" ]]     || die "AZDO_ORG not set — run: specclaw auth azdo"
[[ -n "$AZDO_PROJECT" ]] || die "AZDO_PROJECT not set — run: specclaw auth azdo"
[[ -n "$AZDO_REPO" ]]    || die "AZDO_REPO not set — run: specclaw auth azdo"

STRICT="true"
if [[ -f "$CONFIG_FILE" ]]; then
  _s="$(yaml_val "$CONFIG_FILE" "workflow.strict")"
  [[ -n "$_s" ]] && STRICT="$_s"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Phase Validation ─────────────────────────────────────────────────────────

validate_phase() {
  bash "$SCRIPT_DIR/validate-change.sh" "$SPECCLAW_DIR" "$CHANGE_NAME" pr
}

# ─── Test Policy ──────────────────────────────────────────────────────────────

yaml_set_pr_policy() {
  local policy="$1"
  if grep -q '^pr:' "$CONFIG_FILE" 2>/dev/null; then
    if grep -q '^\s*test_policy:' "$CONFIG_FILE" 2>/dev/null; then
      sed -i "s|^\([[:space:]]*\)test_policy:.*|\1test_policy: \"$policy\"|" "$CONFIG_FILE"
    else
      sed -i "/^pr:/a\\  test_policy: \"$policy\"" "$CONFIG_FILE"
    fi
  else
    printf '\npr:\n  test_policy: "%s"\n' "$policy" >> "$CONFIG_FILE"
  fi
}

check_test_policy() {
  local policy=""
  [[ -f "$CONFIG_FILE" ]] && policy="$(yaml_val "$CONFIG_FILE" "pr.test_policy")"
  if [[ -z "$policy" ]]; then
    echo ""
    echo "SpecClaw: Test Policy Setup"
    echo "----------------------------"
    echo "Do you plan to implement automated tests for this project?"
    echo "This will be enforced on all future PR runs."
    echo ""
    while true; do
      echo -n "Enter policy [none/unit/e2e/both]: "
      read -r policy </dev/tty
      policy="$(echo "$policy" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
      case "$policy" in
        none|unit|e2e|both) break ;;
        *) echo "Invalid. Enter one of: none, unit, e2e, both" ;;
      esac
    done
    yaml_set_pr_policy "$policy"
    echo "Saved test policy: $policy"
    echo ""
  fi
  echo "$policy"
}

enforce_test_policy() {
  local policy="$1"
  [[ "$policy" == "none" ]] && return 0
  local test_cmd=""
  [[ -f "$CONFIG_FILE" ]] && test_cmd="$(yaml_val "$CONFIG_FILE" "build.test_command")"
  [[ -z "$test_cmd" ]] && fail "test_policy is '$policy' but build.test_command is not set in config.yaml"
  local verify_report="$CHANGE_DIR/verify-report.md"
  if [[ ! -s "$verify_report" ]]; then fail "verify-report.md empty — no test evidence (policy: $policy)"; return; fi
  local kw="test|passed|failed|coverage|e2e|unit|assert|spec|describe|expect"
  grep -qiE "$kw" "$verify_report" 2>/dev/null || fail "No test evidence in verify-report.md (policy: $policy)"
  if [[ "$policy" == "e2e" || "$policy" == "both" ]]; then
    grep -qiE "e2e|end.to.end|cypress|playwright|selenium|integration" "$verify_report" 2>/dev/null \
      || fail "No e2e evidence in verify-report.md (policy: $policy)"
  fi
}

report_failures() {
  [[ ${#FAILURES[@]} -eq 0 ]] && return 0
  for msg in "${FAILURES[@]}"; do
    [[ "$STRICT" == "true" ]] && echo "ERROR: $msg" >&2 || echo "WARNING: $msg" >&2
  done
  [[ "$STRICT" == "true" ]] && exit 1
}

# ─── PR Content Builder ───────────────────────────────────────────────────────

extract_section() {
  local file="$1" header="$2" max_lines="${3:-40}"
  local in_section=false count=0 output=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      if [[ "$line" =~ $header ]]; then in_section=true; continue
      elif $in_section; then break; fi
    fi
    if $in_section; then
      output+="$line"$'\n'; ((count++)) || true; [[ $count -ge $max_lines ]] && break
    fi
  done < "$file"
  printf '%s' "$output"
}

build_pr_title() {
  local proposal_file="$CHANGE_DIR/proposal.md"
  local summary=""
  if [[ -f "$proposal_file" ]]; then
    while IFS= read -r line; do
      [[ -z "${line// /}" ]] && continue
      [[ "$line" =~ ^# ]]    && continue
      [[ "$line" =~ ^\*\* ]] && continue
      summary="$line"; break
    done < "$proposal_file"
  fi
  local title
  if [[ -n "$summary" ]]; then
    summary="${summary//\*/}"; summary="${summary//\`/}"
    title="[specclaw] ${CHANGE_NAME}: ${summary}"
  else
    title="[specclaw] ${CHANGE_NAME}"
  fi
  # ADO PR titles: 128 char limit
  [[ ${#title} -gt 128 ]] && title="${title:0:125}..."
  echo "$title"
}

build_pr_description() {
  local policy="$1"
  local proposal_file="$CHANGE_DIR/proposal.md"
  local spec_file="$CHANGE_DIR/spec.md"
  local verify_file="$CHANGE_DIR/verify-report.md"

  local summary_text=""
  if [[ -f "$proposal_file" ]]; then
    local problem solution
    problem="$(extract_section "$proposal_file" "Problem" 10)"
    solution="$(extract_section "$proposal_file" "Proposed Solution" 10)"
    if [[ -n "$problem" || -n "$solution" ]]; then
      summary_text="${problem}${solution}"
    else
      local count=0
      while IFS= read -r line; do
        [[ "$line" =~ ^# ]] && continue
        summary_text+="$line"$'\n'; ((count++)) || true; [[ $count -ge 15 ]] && break
      done < "$proposal_file"
    fi
  else
    summary_text="See change: \`${CHANGE_NAME}\`"
  fi

  local ac_text=""
  if [[ -f "$spec_file" ]]; then
    ac_text="$(extract_section "$spec_file" "Acceptance Criteria" 40)"
    [[ -z "$ac_text" ]] && ac_text="$(head -40 "$spec_file")"
  else
    ac_text="_spec.md not found_"
  fi

  local verdict="unknown" verify_excerpt=""
  if [[ -f "$verify_file" ]]; then
    verdict="$(grep -oiE '\b(PASS|FAIL|PARTIAL)\b' "$verify_file" | head -1)"
    [[ -z "$verdict" ]] && verdict="unknown"
    verify_excerpt="$(head -20 "$verify_file")"
  fi

  local test_section=""
  if [[ "$policy" != "none" && -f "$verify_file" ]]; then
    local test_lines
    test_lines="$(grep -iE "test|passed|failed|coverage|e2e|unit|assert" "$verify_file" | head -10)" || true
    test_section="## Tests
**Policy:** ${policy}

\`\`\`
${test_lines}
\`\`\`
"
  fi

  cat <<EOF
## Summary
${summary_text}
## Acceptance Criteria
${ac_text}
## Verification
**Verdict:** ${verdict}

${verify_excerpt}
${test_section}
---
🤖 Generated by SpecClaw
EOF
}

# ─── ADO REST API ─────────────────────────────────────────────────────────────

adoapi_post() {
  local path="$1" data="$2"
  local url="https://dev.azure.com/${AZDO_ORG}/${AZDO_PROJECT}/_apis/${path}"
  local auth
  auth="$(printf ':%s' "$AZDO_TOKEN" | base64 -w0 2>/dev/null || printf ':%s' "$AZDO_TOKEN" | base64)"
  curl -sf -X POST "$url" \
    -H "Authorization: Basic ${auth}" \
    -H "Content-Type: application/json" \
    -d "$data"
}

adoapi_get() {
  local path="$1"
  local url="https://dev.azure.com/${AZDO_ORG}/${AZDO_PROJECT}/_apis/${path}"
  local auth
  auth="$(printf ':%s' "$AZDO_TOKEN" | base64 -w0 2>/dev/null || printf ':%s' "$AZDO_TOKEN" | base64)"
  curl -sf "$url" -H "Authorization: Basic ${auth}"
}

get_default_branch() {
  local result
  result="$(adoapi_get "git/repositories/${AZDO_REPO}?api-version=7.1" 2>/dev/null)" || true
  if [[ -n "$result" ]]; then
    local branch
    branch="$(echo "$result" | grep -o '"defaultBranch":"[^"]*"' | cut -d'"' -f4)"
    echo "${branch#refs/heads/}"
  else
    echo "main"
  fi
}

json_escape() {
  python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || \
    sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n' | sed 's/\\n$//' | sed 's/^/"/; s/$/"/'
}

save_pr_url() {
  local url="$1"
  local status_file="$CHANGE_DIR/status.md"
  if [[ -f "$status_file" ]]; then
    echo "**ADO PR:** $url" >> "$status_file"
  else
    printf '# Status: %s\n\n**ADO PR:** %s\n' "$CHANGE_NAME" "$url" > "$status_file"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  validate_phase

  local policy
  policy="$(check_test_policy)"

  enforce_test_policy "$policy"
  report_failures

  local source_branch target_branch
  source_branch="$(git rev-parse --abbrev-ref HEAD)"
  target_branch="$(get_default_branch)"

  local title description
  title="$(build_pr_title)"
  description="$(build_pr_description "$policy")"

  local title_json desc_json
  title_json="$(echo "$title" | json_escape)"
  desc_json="$(echo "$description" | json_escape)"

  local payload
  payload=$(printf '{"title":%s,"description":%s,"sourceRefName":"refs/heads/%s","targetRefName":"refs/heads/%s"}' \
    "$title_json" "$desc_json" "$source_branch" "$target_branch")

  echo "Creating ADO PR: $title"
  local response
  response="$(adoapi_post "git/repositories/${AZDO_REPO}/pullrequests?api-version=7.1" "$payload")"

  local pr_id
  pr_id="$(echo "$response" | grep -o '"pullRequestId":[0-9]*' | cut -d: -f2)"
  [[ -n "$pr_id" ]] || die "Failed to parse PR ID from ADO response"

  local pr_url="https://dev.azure.com/${AZDO_ORG}/${AZDO_PROJECT}/_git/${AZDO_REPO}/pullrequest/${pr_id}"
  save_pr_url "$pr_url"
  echo "✅ ADO PR created: $pr_url"
}

main
