#!/usr/bin/env bash
# Validate phase prerequisites and show change status
# Usage: validate-change.sh <specclaw_dir> <change_name> <phase|status>
#
# Checks that required artifacts exist before entering a phase.
# Reads workflow.strict from config.yaml (default: true).
# In strict mode, failures exit 1. In non-strict mode, warnings only.

set -euo pipefail

# --- Help ---
usage() {
  cat <<'EOF'
Usage: validate-change.sh <specclaw_dir> <change_name> <phase|status>

Validate that prerequisites are met before entering a workflow phase,
or show the current status of a change's artifacts.

Arguments:
  specclaw_dir   Path to the .specclaw directory
  change_name    Name of the change (subdirectory under changes/)
  phase          One of: propose, plan, build, verify, archive, github-create
  status         Show artifact status overview

Behavior:
  - Reads workflow.strict from config.yaml (default: true)
  - Runs ALL checks for the phase (does not stop at first failure)
  - strict=true  → failures go to stderr, exit 1
  - strict=false → warnings go to stderr, exit 0
  - All pass     → "✅ Ready for <phase>", exit 0

Examples:
  validate-change.sh .specclaw my-feature build
  validate-change.sh .specclaw my-feature status
EOF
  exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

# --- Args ---
if [[ $# -lt 3 ]]; then
  echo "ERROR: Expected 3 arguments: <specclaw_dir> <change_name> <phase|status>" >&2
  echo "Use --help for usage." >&2
  exit 1
fi

SPECCLAW_DIR="$1"
CHANGE_NAME="$2"
PHASE="$3"

if [[ ! -d "$SPECCLAW_DIR" ]]; then
  echo "ERROR: specclaw directory not found: $SPECCLAW_DIR" >&2
  exit 1
fi

CHANGE_DIR="$SPECCLAW_DIR/changes/$CHANGE_NAME"
CONFIG_FILE="$SPECCLAW_DIR/config.yaml"

# --- Config reading ---
# Read a simple yaml value: yaml_val <file> <dotted.key>
# Handles top-level and one-level nested keys.
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

  # Strip surrounding quotes
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  echo "$value"
}

# Read strict mode (default: true)
STRICT="true"
if [[ -f "$CONFIG_FILE" ]]; then
  local_strict="$(yaml_val "$CONFIG_FILE" "workflow.strict")"
  if [[ -n "$local_strict" ]]; then
    STRICT="$local_strict"
  fi
fi

# --- Helpers ---
FAILURES=()

fail() {
  FAILURES+=("$1")
}

# Count tasks by marker in tasks.md
count_tasks() {
  local file="$1" marker="$2"
  local n
  n=$(grep -c "^- \[${marker}\]" "$file" 2>/dev/null) || true
  echo "${n:-0}"
}

count_incomplete() {
  local file="$1"
  local n
  n=$(grep -cE '^\- \[( |~|!)\]' "$file" 2>/dev/null) || true
  echo "${n:-0}"
}

count_total() {
  local file="$1"
  local n
  n=$(grep -cE '^\- \[.\]' "$file" 2>/dev/null) || true
  echo "${n:-0}"
}

# --- Status subcommand ---
if [[ "$PHASE" == "status" ]]; then
  if [[ ! -d "$CHANGE_DIR" ]]; then
    echo "Change directory not found: $CHANGE_DIR" >&2
    exit 1
  fi

  # Determine phase
  phase_label="unknown"
  if [[ -f "$CHANGE_DIR/verify-report.md" ]]; then
    phase_label="verified"
  elif [[ -f "$CHANGE_DIR/tasks.md" ]]; then
    total=$(count_total "$CHANGE_DIR/tasks.md")
    complete=$(count_tasks "$CHANGE_DIR/tasks.md" "x")
    incomplete=$(count_incomplete "$CHANGE_DIR/tasks.md")
    if [[ "$incomplete" -eq 0 && "$total" -gt 0 ]]; then
      phase_label="build-complete"
    else
      phase_label="building"
    fi
  elif [[ -f "$CHANGE_DIR/spec.md" ]]; then
    phase_label="planned"
  elif [[ -f "$CHANGE_DIR/proposal.md" ]]; then
    phase_label="proposed"
  else
    phase_label="empty"
  fi

  echo "Change: $CHANGE_NAME"
  echo "Phase: $phase_label"
  echo "Artifacts:"

  # proposal.md
  if [[ -f "$CHANGE_DIR/proposal.md" ]]; then
    echo "  ✅ proposal.md"
  else
    echo "  ❌ proposal.md"
  fi

  # spec.md
  if [[ -f "$CHANGE_DIR/spec.md" ]]; then
    echo "  ✅ spec.md"
  else
    echo "  ❌ spec.md"
  fi

  # design.md
  if [[ -f "$CHANGE_DIR/design.md" ]]; then
    echo "  ✅ design.md"
  else
    echo "  ❌ design.md"
  fi

  # tasks.md (with completion count)
  if [[ -f "$CHANGE_DIR/tasks.md" ]]; then
    total=$(count_total "$CHANGE_DIR/tasks.md")
    complete=$(count_tasks "$CHANGE_DIR/tasks.md" "x")
    echo "  ✅ tasks.md ($complete/$total complete)"
  else
    echo "  ❌ tasks.md"
  fi

  # verify-report.md
  if [[ -f "$CHANGE_DIR/verify-report.md" ]]; then
    echo "  ✅ verify-report.md"
  else
    echo "  ❌ verify-report.md"
  fi

  # errors.md
  if [[ -f "$CHANGE_DIR/errors.md" ]]; then
    echo "  ✅ errors.md"
  else
    echo "  ❌ errors.md"
  fi

  # learnings.md
  if [[ -f "$CHANGE_DIR/learnings.md" ]]; then
    echo "  ✅ learnings.md"
  else
    echo "  ❌ learnings.md"
  fi

  # GitHub Issue (if sync configured)
  if [[ -f "$CONFIG_FILE" ]]; then
    gh_sync_val="$(yaml_val "$CONFIG_FILE" "github.sync")"
    if [[ "$gh_sync_val" == "true" ]]; then
      if [[ -f "$CHANGE_DIR/status.md" ]] && grep -q "GitHub Issue" "$CHANGE_DIR/status.md" 2>/dev/null; then
        issue_num="$(grep "GitHub Issue" "$CHANGE_DIR/status.md" | grep -o '#[0-9]*' | head -1)"
        echo "  ✅ GitHub Issue ($issue_num)"
      else
        echo "  ❌ GitHub Issue (sync enabled, not created)"
      fi
    fi
  fi

  exit 0
fi

# --- GitHub issue check helper ---
_check_github_issue() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local gh_sync
    gh_sync="$(yaml_val "$CONFIG_FILE" "github.sync")"
    if [[ "$gh_sync" == "true" ]]; then
      if [[ -f "$CHANGE_DIR/status.md" ]] && grep -q "GitHub Issue" "$CHANGE_DIR/status.md" 2>/dev/null; then
        : # issue exists
      else
        fail "GitHub sync is enabled but no issue created — run gh-sync.sh create first"
      fi
    fi
  fi
}

# --- Phase validation ---
case "$PHASE" in
  propose)
    if [[ -d "$CHANGE_DIR" ]]; then
      fail "Change directory already exists"
    fi
    ;;

  plan)
    if [[ ! -f "$CHANGE_DIR/proposal.md" ]]; then
      fail "Missing proposal.md — run specclaw propose first"
    fi
    # Enforce GitHub issue if sync is configured
    _check_github_issue
    ;;

  build)
    if [[ ! -f "$CHANGE_DIR/spec.md" ]]; then
      fail "Missing spec.md — run specclaw plan first"
    fi
    if [[ ! -f "$CHANGE_DIR/design.md" ]]; then
      fail "Missing design.md — run specclaw plan first"
    fi
    if [[ ! -f "$CHANGE_DIR/tasks.md" ]]; then
      fail "Missing tasks.md — run specclaw plan first"
    fi
    # Enforce GitHub issue if sync is configured
    _check_github_issue
    ;;

  verify)
    if [[ ! -f "$CHANGE_DIR/tasks.md" ]]; then
      fail "Missing tasks.md"
    else
      incomplete=$(count_incomplete "$CHANGE_DIR/tasks.md")
      if [[ "$incomplete" -gt 0 ]]; then
        fail "$incomplete tasks not complete — finish build first"
      fi
    fi
    ;;

  archive)
    if [[ ! -f "$CHANGE_DIR/verify-report.md" ]]; then
      fail "Missing verify-report.md — run specclaw verify first"
    fi
    ;;

  github-create)
    if [[ ! -f "$CHANGE_DIR/proposal.md" ]]; then
      fail "Missing proposal.md — needed for GitHub issue creation"
    fi
    ;;

  *)
    echo "ERROR: Unknown phase '$PHASE'. Expected: propose, plan, build, verify, archive, github-create, status" >&2
    exit 1
    ;;
esac

# --- Report results ---
if [[ ${#FAILURES[@]} -gt 0 ]]; then
  for msg in "${FAILURES[@]}"; do
    if [[ "$STRICT" == "true" ]]; then
      echo "ERROR: $msg" >&2
    else
      echo "WARNING: $msg" >&2
    fi
  done

  if [[ "$STRICT" == "true" ]]; then
    exit 1
  else
    exit 0
  fi
fi

echo "✅ Ready for $PHASE"
exit 0
