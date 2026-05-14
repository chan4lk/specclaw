#!/usr/bin/env bash
# verify-context.sh — Build the full context payload for the Verify Agent
# Part of the specclaw skill. Bash + coreutils only (jq optional).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage: verify-context.sh <specclaw_dir> <change_name>

Build the Verify Agent prompt context by:
  1. Reading config.yaml for project.name and models.review
  2. Collecting evidence via verify.sh collect
  3. Reading spec.md in full
  4. Extracting the Verify Agent prompt template from agent-prompts.md
  5. Filling in template variables
  6. Outputting the complete context payload to stdout

Arguments:
  specclaw_dir   Path to the .specclaw directory
  change_name    Name of the change to verify

Options:
  -h, --help     Show this help message
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

# Read a simple YAML scalar value
# Usage: yaml_val <file> <field_name>
yaml_val() {
  local file="$1" field="$2"
  local val
  val=$(grep -E "^[[:space:]]*${field}:" "$file" 2>/dev/null \
    | head -1 \
    | sed 's/^[^:]*:[[:space:]]*//' \
    | sed 's/^"//' | sed 's/"$//' \
    | sed "s/^'//" | sed "s/'$//")
  printf '%s' "$val"
}

# ─── JSON field extraction ────────────────────────────────────────────────────

# Extract a JSON string field value (top-level) using jq or grep fallback.
# Usage: json_field <json_string> <field_name>
json_field() {
  local json="$1" field="$2"
  if command -v jq &>/dev/null; then
    printf '%s' "$json" | jq -r ".${field} // empty" 2>/dev/null || true
  else
    # Grep fallback — extract value after "field": "..."
    # Handles simple single-line string values
    printf '%s' "$json" | grep -oP "\"${field}\"[[:space:]]*:[[:space:]]*\"\\K[^\"]*" 2>/dev/null | head -1 || true
  fi
}

# Extract a JSON array of strings using jq or grep fallback.
# Usage: json_array <json_string> <field_name>  → outputs one element per line
json_array() {
  local json="$1" field="$2"
  if command -v jq &>/dev/null; then
    printf '%s' "$json" | jq -r ".${field}[]? // empty" 2>/dev/null || true
  else
    # Grep fallback — look for lines that are bare quoted strings inside the array
    # This is fragile but handles the verify.sh output format
    local in_array=false
    while IFS= read -r line; do
      if $in_array; then
        if printf '%s' "$line" | grep -qE '^\s*\]'; then
          break
        fi
        # Extract quoted string value
        local val
        val=$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | sed 's/^"//' | sed 's/",\?$//' | sed 's/"$//')
        [ -n "$val" ] && printf '%s\n' "$val"
      elif printf '%s' "$line" | grep -qE "\"${field}\"[[:space:]]*:"; then
        # Check if array starts on same line or next
        if printf '%s' "$line" | grep -qE '\['; then
          in_array=true
        fi
      fi
    done <<< "$json"
  fi
}

# Extract changed_files array (array of objects) and format as markdown.
# Usage: json_changed_files <json_string>  → outputs formatted markdown
json_changed_files() {
  local json="$1"
  if command -v jq &>/dev/null; then
    printf '%s' "$json" | jq -r '
      .changed_files[]? |
      if .exists then
        "### " + .path + "\n```\n" + .content + "\n```"
      else
        "### " + .path + "\n*File does not exist*"
      end
    ' 2>/dev/null || true
  else
    # Grep-based fallback: extract path and content pairs
    local in_files=false depth=0
    local current_path="" current_content="" in_content=false exists=true
    while IFS= read -r line; do
      if printf '%s' "$line" | grep -qE '"changed_files"[[:space:]]*:'; then
        in_files=true
        continue
      fi
      if ! $in_files; then continue; fi

      # Detect path
      if printf '%s' "$line" | grep -qE '"path"[[:space:]]*:'; then
        current_path=$(printf '%s' "$line" | sed 's/.*"path"[[:space:]]*:[[:space:]]*//' | sed 's/^"//' | sed 's/",\?$//' | sed 's/"$//')
      fi

      # Detect exists
      if printf '%s' "$line" | grep -qE '"exists"[[:space:]]*:[[:space:]]*false'; then
        exists=false
      elif printf '%s' "$line" | grep -qE '"exists"[[:space:]]*:[[:space:]]*true'; then
        exists=true
      fi

      # Detect content field
      if printf '%s' "$line" | grep -qE '"content"[[:space:]]*:'; then
        local val
        val=$(printf '%s' "$line" | sed 's/.*"content"[[:space:]]*:[[:space:]]*//')
        if printf '%s' "$val" | grep -qE '^null'; then
          current_content=""
        else
          current_content=$(printf '%s' "$val" | sed 's/^"//' | sed 's/",\?$//' | sed 's/"$//')
        fi
      fi

      # End of an object in the array — emit
      if printf '%s' "$line" | grep -qE '^\s*\}'; then
        if [ -n "$current_path" ]; then
          if $exists && [ -n "$current_content" ]; then
            # Unescape JSON newlines for display
            local decoded
            decoded=$(printf '%s' "$current_content" | sed 's/\\n/\n/g' | sed 's/\\t/\t/g' | sed 's/\\"/"/g' | sed 's/\\\\/\\/g')
            printf '### %s\n```\n%s\n```\n' "$current_path" "$decoded"
          else
            printf '### %s\n*File does not exist*\n' "$current_path"
          fi
        fi
        current_path=""
        current_content=""
        exists=true
      fi

      # Detect end of changed_files array
      if printf '%s' "$line" | grep -qE '^\s*\]' && $in_files; then
        # Could be end of changed_files — heuristic: break after first top-level ]
        break
      fi
    done <<< "$json"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

[ $# -ge 2 ] || { usage >&2; exit 1; }

SPECCLAW_DIR="$1"
CHANGE_NAME="$2"
CHANGE_DIR="${SPECCLAW_DIR}/changes/${CHANGE_NAME}"
CONFIG_FILE="${SPECCLAW_DIR}/config.yaml"
SPEC_FILE="${CHANGE_DIR}/spec.md"

# Validate
[ -d "$SPECCLAW_DIR" ] || die "specclaw directory not found: ${SPECCLAW_DIR}"
[ -d "$CHANGE_DIR" ] || die "Change directory not found: ${CHANGE_DIR}"
[ -f "$CONFIG_FILE" ] || die "config.yaml not found: ${CONFIG_FILE}"
[ -f "$SPEC_FILE" ] || die "spec.md not found: ${SPEC_FILE}"

# ─── Step 1: Read config ─────────────────────────────────────────────────────

PROJECT_NAME=$(yaml_val "$CONFIG_FILE" "name")
MODEL_REVIEW=$(yaml_val "$CONFIG_FILE" "review")

[ -n "$PROJECT_NAME" ] || warn "Could not read project.name from config.yaml"
[ -n "$MODEL_REVIEW" ] || warn "Could not read models.review from config.yaml"

# ─── Step 2: Collect evidence ────────────────────────────────────────────────

EVIDENCE_JSON=$("$SCRIPT_DIR/verify.sh" collect "$SPECCLAW_DIR" "$CHANGE_NAME")
[ -n "$EVIDENCE_JSON" ] || die "verify.sh collect returned empty output"

# ─── Step 3: Read spec.md ────────────────────────────────────────────────────

SPEC_CONTENT=$(cat "$SPEC_FILE")

# ─── Step 4: Extract Verify Agent template from agent-prompts.md ─────────────

PROMPTS_FILE="$SCRIPT_DIR/../references/agent-prompts.md"
[ -f "$PROMPTS_FILE" ] || die "agent-prompts.md not found: ${PROMPTS_FILE}"

# Extract from "## Verify Agent" to the next "## " header or EOF
# Must track code fences so that ## headers inside ``` blocks don't end extraction early.
TEMPLATE_FILE=$(mktemp)
awk '
  /^## Verify Agent/ { found=1; next }
  found && /^```/ { in_fence = !in_fence }
  found && !in_fence && /^## / { exit }
  found { print }
' "$PROMPTS_FILE" > "$TEMPLATE_FILE"

# Strip leading/trailing blank lines
sed -i '/./,$!d' "$TEMPLATE_FILE"
# Remove trailing blank lines
sed -i -e :a -e '/^\s*$/{ $d; N; ba; }' "$TEMPLATE_FILE"

# If the template is wrapped in a code fence, strip first and last fence lines
if head -1 "$TEMPLATE_FILE" | grep -qE '^\s*```'; then
  sed -i '1d' "$TEMPLATE_FILE"
  sed -i '${ /^```/d }' "$TEMPLATE_FILE"
fi

[ -s "$TEMPLATE_FILE" ] || die "Could not extract Verify Agent template from agent-prompts.md"

# ─── Step 5: Extract evidence fields to temp files ───────────────────────────

TMPDIR_CTX=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CTX" "$TEMPLATE_FILE"' EXIT

# Acceptance criteria — one per line
json_array "$EVIDENCE_JSON" "acceptance_criteria" > "$TMPDIR_CTX/acceptance_criteria"
[ -s "$TMPDIR_CTX/acceptance_criteria" ] || echo "No acceptance criteria found" > "$TMPDIR_CTX/acceptance_criteria"

# Changed files — formatted as markdown
json_changed_files "$EVIDENCE_JSON" > "$TMPDIR_CTX/changed_files_content"
[ -s "$TMPDIR_CTX/changed_files_content" ] || echo "No changed files found" > "$TMPDIR_CTX/changed_files_content"

# Test, lint, build output
json_field "$EVIDENCE_JSON" "test_output" > "$TMPDIR_CTX/test_output"
[ -s "$TMPDIR_CTX/test_output" ] || echo "No tests configured" > "$TMPDIR_CTX/test_output"

json_field "$EVIDENCE_JSON" "lint_output" > "$TMPDIR_CTX/lint_output"
[ -s "$TMPDIR_CTX/lint_output" ] || echo "No linter configured" > "$TMPDIR_CTX/lint_output"

json_field "$EVIDENCE_JSON" "build_output" > "$TMPDIR_CTX/build_output"
[ -s "$TMPDIR_CTX/build_output" ] || echo "No build command configured" > "$TMPDIR_CTX/build_output"

# Spec and change name
cat "$SPEC_FILE" > "$TMPDIR_CTX/spec_content"
printf '%s' "$CHANGE_NAME" > "$TMPDIR_CTX/change_name"

# ─── Step 6: Perform template substitution and output ────────────────────────

# replace_var: replace {{varname}} in TEMPLATE_FILE with contents of a file
# Uses awk with file reading to handle multi-line content safely.
replace_var() {
  local varname="$1"
  local valfile="$2"
  local outfile
  outfile=$(mktemp)

  awk -v placeholder="{{${varname}}}" -v valfile="$valfile" '
    BEGIN {
      # Read replacement content from file
      replacement = ""
      while ((getline line < valfile) > 0) {
        if (replacement != "") replacement = replacement "\n"
        replacement = replacement line
      }
      close(valfile)
    }
    {
      idx = index($0, placeholder)
      if (idx > 0) {
        before = substr($0, 1, idx - 1)
        after = substr($0, idx + length(placeholder))
        print before replacement after
      } else {
        print
      }
    }
  ' "$TEMPLATE_FILE" > "$outfile"

  mv "$outfile" "$TEMPLATE_FILE"
}

replace_var "change_name" "$TMPDIR_CTX/change_name"
replace_var "spec_content" "$TMPDIR_CTX/spec_content"
replace_var "acceptance_criteria" "$TMPDIR_CTX/acceptance_criteria"
replace_var "changed_files_content" "$TMPDIR_CTX/changed_files_content"
replace_var "test_output" "$TMPDIR_CTX/test_output"
replace_var "lint_output" "$TMPDIR_CTX/lint_output"
replace_var "build_output" "$TMPDIR_CTX/build_output"

cat "$TEMPLATE_FILE"
