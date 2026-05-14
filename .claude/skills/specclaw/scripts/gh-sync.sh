#!/usr/bin/env bash
# gh-sync.sh — GitHub Issues sync for specclaw changes
# Part of the specclaw skill. Bash + gh CLI or curl only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage: gh-sync.sh <subcommand> [options]

Subcommands:
  setup    [--config <config.yaml>]
           Verify auth, create label, confirm readiness.

  create   <specclaw_dir> <change_name>
           Create a GitHub issue from proposal.md and tasks.md.

  update   <specclaw_dir> <change_name>
           Update issue body with current task statuses.

  comment  <specclaw_dir> <change_name> "<text>"
           Post a comment on the change's issue.

  close    <specclaw_dir> <change_name>
           Close the change's issue with a completion comment.

Options:
  -h, --help   Show this help message
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

# Read a simple yaml value: yaml_val <file> <dotted.key>
# Handles top-level and one-level nested keys (same as build.sh).
yaml_val() {
  local file="$1" key="$2"
  local section field
  if [[ "$key" == *.* ]]; then
    section="${key%%.*}"
    field="${key#*.}"
  else
    section=""
    field="$key"
  fi

  local in_section=false value=""
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    if [[ -z "$section" ]]; then
      if [[ "$line" =~ ^${field}:[[:space:]]*(.*) ]]; then
        value="${BASH_REMATCH[1]}"
        break
      fi
    else
      if [[ "$line" =~ ^[a-zA-Z_] ]]; then
        if [[ "$line" =~ ^${section}: ]]; then
          in_section=true
        else
          in_section=false
        fi
        continue
      fi
      if $in_section; then
        if [[ "$line" =~ ^[[:space:]]+${field}:[[:space:]]*(.*) ]]; then
          value="${BASH_REMATCH[1]}"
          break
        fi
      fi
    fi
  done < "$file"

  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  echo "$value"
}

# JSON-escape a string (for curl payloads)
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  # Escape newlines
  s="${s//$'\n'/\\n}"
  # Escape tabs
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ─── Auth Detection ───────────────────────────────────────────────────────────
# Sets AUTH_METHOD ("gh" or "curl") and TOKEN (for curl mode)

detect_auth() {
  local config_file="${1:-}"

  # Collect all available auth methods, then verify in order
  # This ensures fallback if a token is expired/invalid

  # Try GITHUB_TOKEN env first (most explicit)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    if _verify_token "$GITHUB_TOKEN"; then
      AUTH_METHOD="curl"
      TOKEN="$GITHUB_TOKEN"
      return 0
    else
      warn "GITHUB_TOKEN is set but failed auth check — trying fallbacks"
    fi
  fi

  # Try config.yaml github.token
  if [[ -n "$config_file" && -f "$config_file" ]]; then
    local cfg_token
    cfg_token="$(yaml_val "$config_file" "github.token")"
    if [[ -n "$cfg_token" ]]; then
      if _verify_token "$cfg_token"; then
        AUTH_METHOD="curl"
        TOKEN="$cfg_token"
        return 0
      else
        warn "config.yaml github.token failed auth check — trying fallbacks"
      fi
    fi
  fi

  # Try gh CLI (fallback)
  if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    AUTH_METHOD="gh"
    return 0
  fi

  die "No working GitHub auth found. Either:
  1. Set GITHUB_TOKEN environment variable (with a valid PAT)
  2. Add github.token to config.yaml
  3. Install and auth gh CLI: gh auth login"
}

# Verify a GitHub token works by hitting /user endpoint
_verify_token() {
  local token="$1"
  local http_code
  http_code="$(curl -s -w '%{http_code}' -o /dev/null \
    "https://api.github.com/user" \
    -H "Authorization: token $token" \
    -H "Accept: application/vnd.github.v3+json" 2>/dev/null)" || true
  [[ "$http_code" -lt 400 ]]
}

# ─── Repo Detection ──────────────────────────────────────────────────────────
# Sets REPO (owner/repo format)

detect_repo() {
  local config_file="${1:-}"

  # 1. config.yaml github.repo?
  if [[ -n "$config_file" && -f "$config_file" ]]; then
    local cfg_repo
    cfg_repo="$(yaml_val "$config_file" "github.repo")"
    if [[ -n "$cfg_repo" ]]; then
      REPO="$cfg_repo"
      return 0
    fi
  fi

  # 2. Parse from git remote
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null)" || die "No git remote 'origin' found and github.repo not in config"

  if [[ "$remote_url" =~ git@github\.com:(.+) ]]; then
    REPO="${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ https://github\.com/(.+) ]]; then
    REPO="${BASH_REMATCH[1]}"
  else
    die "Cannot parse GitHub repo from remote URL: $remote_url"
  fi

  # Strip .git suffix
  REPO="${REPO%.git}"
}

# ─── Config ───────────────────────────────────────────────────────────────────

find_config() {
  local specclaw_dir="${1:-}"
  if [[ -n "$specclaw_dir" && -f "$specclaw_dir/config.yaml" ]]; then
    echo "$specclaw_dir/config.yaml"
  else
    echo ""
  fi
}

get_label() {
  local config_file="${1:-}"
  local label=""
  if [[ -n "$config_file" && -f "$config_file" ]]; then
    label="$(yaml_val "$config_file" "github.label")"
  fi
  echo "${label:-specclaw}"
}

# ─── Issue Number from status.md ──────────────────────────────────────────────

get_issue_number() {
  local change_dir="$1"
  local status_file="$change_dir/status.md"

  [[ -f "$status_file" ]] || die "No status.md found in $change_dir (run 'create' first)"

  local issue_ref
  issue_ref="$(grep "GitHub Issue" "$status_file" | grep -o '#[0-9]*' | head -1)" || true

  [[ -n "$issue_ref" ]] || die "No GitHub Issue reference found in $status_file"

  # Strip the # prefix
  echo "${issue_ref#\#}"
}

# ─── API Wrappers ─────────────────────────────────────────────────────────────

# curl wrapper that checks HTTP status
api_curl() {
  local method="$1" url="$2" data="${3:-}"
  local response http_code

  local tmp
  tmp="$(mktemp)"
  trap "rm -f '$tmp'" RETURN

  if [[ -n "$data" ]]; then
    http_code="$(curl -s -w '%{http_code}' -o "$tmp" -X "$method" "$url" \
      -H "Authorization: token $TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Content-Type: application/json" \
      -d "$data")"
  else
    http_code="$(curl -s -w '%{http_code}' -o "$tmp" -X "$method" "$url" \
      -H "Authorization: token $TOKEN" \
      -H "Accept: application/vnd.github.v3+json")"
  fi

  response="$(cat "$tmp")"

  if [[ "$http_code" -ge 400 ]]; then
    local msg
    msg="$(echo "$response" | grep -o '"message":"[^"]*"' | head -1 | sed 's/"message":"//;s/"$//')" || true
    die "GitHub API error ($http_code): ${msg:-$response}"
  fi

  echo "$response"
}

# Create an issue. Returns the full JSON response.
api_create_issue() {
  local title="$1" body="$2" label="$3"
  local esc_title esc_body esc_label

  esc_title="$(json_escape "$title")"
  esc_body="$(json_escape "$body")"
  esc_label="$(json_escape "$label")"

  if [[ "$AUTH_METHOD" == "gh" ]]; then
    gh issue create --repo "$REPO" --title "$title" --body "$body" --label "$label" 2>&1
  else
    api_curl POST "https://api.github.com/repos/$REPO/issues" \
      "{\"title\":\"$esc_title\",\"body\":\"$esc_body\",\"labels\":[\"$esc_label\"]}"
  fi
}

# Update an issue body
api_update_issue() {
  local issue_num="$1" body="$2"
  local esc_body
  esc_body="$(json_escape "$body")"

  if [[ "$AUTH_METHOD" == "gh" ]]; then
    gh issue edit "$issue_num" --repo "$REPO" --body "$body"
  else
    api_curl PATCH "https://api.github.com/repos/$REPO/issues/$issue_num" \
      "{\"body\":\"$esc_body\"}"
  fi
}

# Comment on an issue
api_comment_issue() {
  local issue_num="$1" comment="$2"
  local esc_comment
  esc_comment="$(json_escape "$comment")"

  if [[ "$AUTH_METHOD" == "gh" ]]; then
    gh issue comment "$issue_num" --repo "$REPO" --body "$comment"
  else
    api_curl POST "https://api.github.com/repos/$REPO/issues/$issue_num/comments" \
      "{\"body\":\"$esc_comment\"}"
  fi
}

# Close an issue with a comment
api_close_issue() {
  local issue_num="$1" comment="$2"
  local esc_comment
  esc_comment="$(json_escape "$comment")"

  if [[ "$AUTH_METHOD" == "gh" ]]; then
    gh issue close "$issue_num" --repo "$REPO" --comment "$comment"
  else
    # Post comment first
    api_curl POST "https://api.github.com/repos/$REPO/issues/$issue_num/comments" \
      "{\"body\":\"$esc_comment\"}"
    # Then close
    api_curl PATCH "https://api.github.com/repos/$REPO/issues/$issue_num" \
      '{"state":"closed"}'
  fi
}

# Create label (idempotent)
api_create_label() {
  local label="$1"

  if [[ "$AUTH_METHOD" == "gh" ]]; then
    gh label create "$label" --repo "$REPO" --color "FF6B35" --description "SpecClaw managed" --force 2>&1 || true
  else
    local esc_label esc_desc
    esc_label="$(json_escape "$label")"
    esc_desc="$(json_escape "SpecClaw managed")"
    # Try create; ignore 422 (already exists)
    local response http_code tmp
    tmp="$(mktemp)"
    http_code="$(curl -s -w '%{http_code}' -o "$tmp" -X POST \
      "https://api.github.com/repos/$REPO/labels" \
      -H "Authorization: token $TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"$esc_label\",\"color\":\"FF6B35\",\"description\":\"$esc_desc\"}")"
    rm -f "$tmp"
    if [[ "$http_code" -ge 400 && "$http_code" -ne 422 ]]; then
      warn "Could not create label '$label' (HTTP $http_code), continuing anyway"
    fi
  fi
}

# Verify auth works
api_verify_auth() {
  if [[ "$AUTH_METHOD" == "gh" ]]; then
    gh auth status &>/dev/null || die "gh auth verification failed"
  else
    local http_code
    http_code="$(curl -s -w '%{http_code}' -o /dev/null \
      "https://api.github.com/repos/$REPO" \
      -H "Authorization: token $TOKEN" \
      -H "Accept: application/vnd.github.v3+json")"
    [[ "$http_code" -lt 400 ]] || die "GitHub API auth verification failed (HTTP $http_code)"
  fi
}

# ─── Task Checklist Builder ───────────────────────────────────────────────────

# Build a markdown checklist from tasks.md
# Args: <tasks.md path> [include_status]
# If include_status is "true", marks complete tasks as [x] and failed as ⚠️
build_task_checklist() {
  local tasks_file="$1"
  local include_status="${2:-false}"
  local checklist=""
  local current_wave=""

  [[ -f "$tasks_file" ]] || { echo "Planning pending"; return; }

  while IFS= read -r line; do
    # Detect wave headers: ### Wave N ...
    if [[ "$line" =~ ^###?[[:space:]]+Wave[[:space:]]+([0-9]+) ]]; then
      current_wave="${BASH_REMATCH[1]}"
      continue
    fi

    # Detect task lines in SpecClaw format: - [x] `T1` — Title
    # Also support: - **T1** — Title
    local task_id="" task_title="" task_status=""

    if [[ "$line" =~ ^-[[:space:]]+\[(.)\][[:space:]]+\`([Tt][0-9]+)\`[[:space:]]*[—–-][[:space:]]*(.*) ]]; then
      local marker="${BASH_REMATCH[1]}"
      task_id="${BASH_REMATCH[2]}"
      task_title="${BASH_REMATCH[3]}"
      case "$marker" in
        x) task_status="complete" ;;
        '~') task_status="in_progress" ;;
        '!') task_status="failed" ;;
        *) task_status="pending" ;;
      esac
    elif [[ "$line" =~ ^-[[:space:]]+\*\*([Tt][0-9]+)\*\*[[:space:]]*[—:–-][[:space:]]*(.*) ]]; then
      task_id="${BASH_REMATCH[1]}"
      task_title="${BASH_REMATCH[2]}"
      task_status="pending"
    fi

    if [[ -n "$task_id" ]]; then
      local wave_suffix=""
      [[ -n "$current_wave" ]] && wave_suffix=" (Wave $current_wave)"

      local checkbox="[ ]"
      local suffix=""

      if [[ "$include_status" == "true" ]]; then
        if [[ "$task_status" == "complete" ]]; then
          checkbox="[x]"
        elif [[ "$task_status" == "failed" ]]; then
          suffix=" ⚠️"
        fi
      fi

      checklist+="- $checkbox $task_id — ${task_title%%$'\n'*}${wave_suffix}${suffix}"$'\n'
    fi
  done < "$tasks_file"

  if [[ -z "$checklist" ]]; then
    echo "Planning pending"
  else
    printf '%s' "$checklist"
  fi
}

# Count task statuses from tasks.md for the update command
# Reads status from status.md or tasks.md task entries
count_task_statuses() {
  local change_dir="$1"
  local tasks_file="$change_dir/tasks.md"
  local status_file="$change_dir/status.md"
  local total=0 complete=0

  [[ -f "$tasks_file" ]] || { echo "0 0"; return; }

  # Parse tasks from tasks.md — support both `- [x] \`T1\`` and `- **T1**` formats
  while IFS= read -r line; do
    if [[ "$line" =~ ^-[[:space:]]+\[.\][[:space:]]+\`[Tt][0-9]+\` ]]; then
      ((total++)) || true
      if [[ "$line" =~ ^-[[:space:]]+\[x\] ]]; then
        ((complete++)) || true
      fi
    elif [[ "$line" =~ ^-[[:space:]]+\*\*[Tt][0-9]+\*\* ]]; then
      ((total++)) || true
    fi
  done < "$tasks_file"

  echo "$total $complete"
}

# Build updated checklist from tasks.md + status.md for update command
build_updated_checklist() {
  local change_dir="$1"
  local tasks_file="$change_dir/tasks.md"
  local status_file="$change_dir/status.md"
  local checklist=""
  local current_wave=""
  local total=0 complete=0

  [[ -f "$tasks_file" ]] || { echo "Planning pending"; echo "0 0" >&2; return; }

  # Build a map of task statuses from status.md
  declare -A task_statuses
  if [[ -f "$status_file" ]]; then
    while IFS= read -r line; do
      # Match lines like: - **T1** — Title... status/emoji indicators
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\*\*([Tt][0-9]+)\*\* ]]; then
        local sid="${BASH_REMATCH[1]^^}"  # uppercase
        if [[ "$line" =~ ✅ ]] || [[ "$line" =~ complete ]]; then
          task_statuses["$sid"]="complete"
        elif [[ "$line" =~ ❌ ]] || [[ "$line" =~ failed ]]; then
          task_statuses["$sid"]="failed"
        elif [[ "$line" =~ 🔄 ]] || [[ "$line" =~ in.progress ]]; then
          task_statuses["$sid"]="in_progress"
        fi
      fi
    done < "$status_file"
  fi

  while IFS= read -r line; do
    if [[ "$line" =~ ^###?[[:space:]]+Wave[[:space:]]+([0-9]+) ]]; then
      current_wave="${BASH_REMATCH[1]}"
      continue
    fi

    local task_id="" task_title="" task_status=""

    # SpecClaw format: - [x] `T1` — Title
    if [[ "$line" =~ ^-[[:space:]]+\[(.)\][[:space:]]+\`([Tt][0-9]+)\`[[:space:]]*[—–-][[:space:]]*(.*) ]]; then
      local marker="${BASH_REMATCH[1]}"
      task_id="${BASH_REMATCH[2]^^}"
      task_title="${BASH_REMATCH[3]}"
      case "$marker" in
        x) task_status="complete" ;;
        '~') task_status="in_progress" ;;
        '!') task_status="failed" ;;
        *) task_status="pending" ;;
      esac
    # Alt format: - **T1** — Title
    elif [[ "$line" =~ ^-[[:space:]]+\*\*([Tt][0-9]+)\*\*[[:space:]]*[—:–-][[:space:]]*(.*) ]]; then
      task_id="${BASH_REMATCH[1]^^}"
      task_title="${BASH_REMATCH[2]}"
      task_status="pending"
    fi

    if [[ -n "$task_id" ]]; then
      local wave_suffix=""
      [[ -n "$current_wave" ]] && wave_suffix=" (Wave $current_wave)"

      ((total++)) || true

      local checkbox="[ ]"
      local suffix=""

      # Check status.md map first, then fall back to tasks.md marker
      local status="${task_statuses[$task_id]:-$task_status}"

      case "$status" in
        complete)
          checkbox="[x]"
          ((complete++)) || true
          ;;
        failed)
          suffix=" ⚠️"
          ;;
      esac

      checklist+="- $checkbox $task_id — ${task_title%%$'\n'*}${wave_suffix}${suffix}"$'\n'
    fi
  done < "$tasks_file"

  printf '%s' "$checklist"
  # Output counts on stderr for capture
  echo "$complete $total" >&2
}

# ─── Issue Body Builder ──────────────────────────────────────────────────────

build_issue_body() {
  local change_name="$1" proposal_content="$2" task_checklist="$3"

  # Trim proposal to 2000 chars if very long
  if [[ ${#proposal_content} -gt 2000 ]]; then
    proposal_content="${proposal_content:0:2000}..."
  fi

  cat <<EOF
## 🦞 SpecClaw: $change_name

**Change:** \`$change_name\`

### Proposal
$proposal_content

### Tasks
$task_checklist

---
*Managed by [SpecClaw](https://github.com/chanbistec/specclaw)*
EOF
}

# ─── Subcommands ──────────────────────────────────────────────────────────────

cmd_setup() {
  local config_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config) config_file="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  detect_auth "$config_file"
  detect_repo "$config_file"

  local label
  label="$(get_label "$config_file")"

  api_verify_auth
  api_create_label "$label"

  echo "✅ GitHub sync ready for $REPO"
}

cmd_create() {
  local specclaw_dir="$1"
  local change_name="$2"
  local config_file
  config_file="$(find_config "$specclaw_dir")"

  detect_auth "$config_file"
  detect_repo "$config_file"

  local label
  label="$(get_label "$config_file")"

  local change_dir="$specclaw_dir/changes/$change_name"
  [[ -d "$change_dir" ]] || die "Change directory not found: $change_dir"

  # Read proposal
  local proposal_file="$change_dir/proposal.md"
  [[ -f "$proposal_file" ]] || die "proposal.md not found in $change_dir"
  local proposal_content
  proposal_content="$(cat "$proposal_file")"

  # Build task checklist
  local task_checklist
  local tasks_file="$change_dir/tasks.md"
  task_checklist="$(build_task_checklist "$tasks_file" false)"

  # Build issue body
  local body
  body="$(build_issue_body "$change_name" "$proposal_content" "$task_checklist")"

  local title="🦞 $change_name"

  # Create issue
  local response
  response="$(api_create_issue "$title" "$body" "$label")"

  # Extract issue number
  local issue_num=""
  if [[ "$AUTH_METHOD" == "gh" ]]; then
    # gh outputs the issue URL like https://github.com/owner/repo/issues/42
    issue_num="$(echo "$response" | grep -o '/issues/[0-9]*' | grep -o '[0-9]*' | head -1)" || true
  else
    # JSON response: "number": 42
    issue_num="$(echo "$response" | grep -o '"number":[[:space:]]*[0-9]*' | grep -o '[0-9]*' | head -1)" || true
  fi

  [[ -n "$issue_num" ]] || die "Failed to extract issue number from API response"

  # Update status.md
  local status_file="$change_dir/status.md"
  if [[ ! -f "$status_file" ]]; then
    cat > "$status_file" <<STATUSEOF
# Status: $change_name

**Status:** planning
**GitHub Issue:** #$issue_num
STATUSEOF
  else
    echo "**GitHub Issue:** #$issue_num" >> "$status_file"
  fi

  echo "Created issue #$issue_num for $change_name"
}

cmd_update() {
  local specclaw_dir="$1"
  local change_name="$2"
  local config_file
  config_file="$(find_config "$specclaw_dir")"

  detect_auth "$config_file"
  detect_repo "$config_file"

  local change_dir="$specclaw_dir/changes/$change_name"
  [[ -d "$change_dir" ]] || die "Change directory not found: $change_dir"

  local issue_num
  issue_num="$(get_issue_number "$change_dir")"

  # Build updated checklist (counts come on stderr)
  local task_checklist counts complete total
  counts_file="$(mktemp)"
  task_checklist="$(build_updated_checklist "$change_dir" 2>"$counts_file")"
  counts="$(cat "$counts_file")"
  rm -f "$counts_file"
  complete="${counts%% *}"
  total="${counts##* }"

  # Read proposal for body rebuild
  local proposal_content=""
  local proposal_file="$change_dir/proposal.md"
  if [[ -f "$proposal_file" ]]; then
    proposal_content="$(cat "$proposal_file")"
  fi

  local body
  body="$(build_issue_body "$change_name" "$proposal_content" "$task_checklist")"

  api_update_issue "$issue_num" "$body" >/dev/null

  echo "Updated issue #$issue_num ($complete/$total tasks complete)"
}

cmd_comment() {
  local specclaw_dir="$1"
  local change_name="$2"
  local comment_text="$3"
  local config_file
  config_file="$(find_config "$specclaw_dir")"

  detect_auth "$config_file"
  detect_repo "$config_file"

  local change_dir="$specclaw_dir/changes/$change_name"
  [[ -d "$change_dir" ]] || die "Change directory not found: $change_dir"

  local issue_num
  issue_num="$(get_issue_number "$change_dir")"

  api_comment_issue "$issue_num" "$comment_text" >/dev/null

  echo "Commented on issue #$issue_num"
}

cmd_close() {
  local specclaw_dir="$1"
  local change_name="$2"
  local config_file
  config_file="$(find_config "$specclaw_dir")"

  detect_auth "$config_file"
  detect_repo "$config_file"

  local change_dir="$specclaw_dir/changes/$change_name"
  [[ -d "$change_dir" ]] || die "Change directory not found: $change_dir"

  local issue_num
  issue_num="$(get_issue_number "$change_dir")"

  local comment="✅ Change completed and archived by SpecClaw"
  api_close_issue "$issue_num" "$comment" >/dev/null

  echo "Closed issue #$issue_num"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

[[ $# -gt 0 ]] || { usage; exit 1; }

case "$1" in
  -h|--help)
    usage
    exit 0
    ;;
  setup)
    shift
    cmd_setup "$@"
    ;;
  create)
    shift
    [[ $# -ge 2 ]] || die "Usage: gh-sync.sh create <specclaw_dir> <change_name>"
    cmd_create "$1" "$2"
    ;;
  update)
    shift
    [[ $# -ge 2 ]] || die "Usage: gh-sync.sh update <specclaw_dir> <change_name>"
    cmd_update "$1" "$2"
    ;;
  comment)
    shift
    [[ $# -ge 3 ]] || die "Usage: gh-sync.sh comment <specclaw_dir> <change_name> \"<text>\""
    cmd_comment "$1" "$2" "$3"
    ;;
  close)
    shift
    [[ $# -ge 2 ]] || die "Usage: gh-sync.sh close <specclaw_dir> <change_name>"
    cmd_close "$1" "$2"
    ;;
  *)
    die "Unknown subcommand: $1. Use --help for usage."
    ;;
esac
