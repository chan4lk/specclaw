#!/usr/bin/env bash
# verify.sh — Evidence collection and test execution for specclaw verification
# Part of the specclaw skill. Bash + coreutils only (jq optional for validation).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage: verify.sh <subcommand> [options]

Subcommands:
  collect       <specclaw_dir> <change_name>
                Collect evidence: acceptance criteria, file contents, test results.
                Outputs JSON to stdout.

  report        <specclaw_dir> <change_name>
                Read verify-report.md and output verdict summary.

  update-status <specclaw_dir> <change_name> <verdict>
                Update the Verify row in status.md.
                verdict: PASS | FAIL | PARTIAL

Options:
  -h, --help    Show this help message
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

# JSON-escape a string: backslashes, quotes, newlines, tabs, carriage returns
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Read a YAML value (simple single-line scalar) from config.yaml
# Usage: yaml_val <file> <dotted.key>
# e.g. yaml_val config.yaml build.test_command
yaml_val() {
  local file="$1" key="$2"
  local field="${key##*.}"
  local val
  val=$(grep -E "^[[:space:]]*${field}:" "$file" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//")
  printf '%s' "$val"
}

# Run a command, capture output (capped at 100 lines), return exit code
# Usage: run_capped <varname_output> <command_string>
# Sets: <varname_output> to captured output, returns command exit code
run_capped() {
  local -n _out_ref="$1"
  local cmd="$2"
  local tmpfile
  tmpfile=$(mktemp)
  local rc=0
  eval "$cmd" >"$tmpfile" 2>&1 || rc=$?
  _out_ref=$(head -100 "$tmpfile")
  local total
  total=$(wc -l < "$tmpfile")
  if [ "$total" -gt 100 ]; then
    _out_ref="${_out_ref}
... (truncated, ${total} total lines)"
  fi
  rm -f "$tmpfile"
  return "$rc"
}

# ─── Subcommand: collect ──────────────────────────────────────────────────────

cmd_collect() {
  local specclaw_dir="$1"
  local change_name="$2"
  local change_dir="${specclaw_dir}/changes/${change_name}"

  # Validate required files
  local spec_file="${change_dir}/spec.md"
  local tasks_file="${change_dir}/tasks.md"
  local config_file="${specclaw_dir}/config.yaml"

  [ -f "$spec_file" ] || die "spec.md not found at ${spec_file}"
  [ -f "$tasks_file" ] || die "tasks.md not found at ${tasks_file}"

  # 1. Extract acceptance criteria
  local ac_lines=()
  while IFS= read -r line; do
    # Strip the checkbox prefix and bold markers to get clean AC text
    local clean
    clean=$(printf '%s' "$line" | sed 's/^[[:space:]]*- \[ \] \*\*//' | sed 's/^[[:space:]]*- \[ \] //' | sed 's/\*\*$//' | sed 's/\*\*//')
    ac_lines+=("$clean")
  done < <(grep -E '^\s*- \[ \] (\*\*)?AC-' "$spec_file" || true)

  # 2. Collect file paths from tasks.md Files: fields
  local file_paths=()
  while IFS= read -r line; do
    # Files: field contains comma-separated paths like `path1`, `path2`
    local paths_str
    paths_str=$(printf '%s' "$line" | sed 's/^[^:]*:[[:space:]]*//')
    # Extract backtick-delimited paths
    while [[ "$paths_str" =~ \`([^\`]+)\` ]]; do
      file_paths+=("${BASH_REMATCH[1]}")
      paths_str="${paths_str#*\`${BASH_REMATCH[1]}\`}"
    done
    # If no backticks, try comma-separated plain text
    if [ ${#file_paths[@]} -eq 0 ] 2>/dev/null; then
      IFS=',' read -ra parts <<< "$paths_str"
      for p in "${parts[@]}"; do
        p=$(printf '%s' "$p" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        [ -n "$p" ] && file_paths+=("$p")
      done
    fi
  done < <(grep -iE '^\s*\*?\*?Files\*?\*?\s*:' "$tasks_file" || true)

  # Deduplicate file paths
  local unique_paths=()
  local -A seen_paths=()
  for fp in "${file_paths[@]}"; do
    if [ -z "${seen_paths[$fp]+x}" ]; then
      seen_paths[$fp]=1
      unique_paths+=("$fp")
    fi
  done

  # 3. Read each file's content
  local files_json=""
  for fp in "${unique_paths[@]}"; do
    local full_path
    # Resolve relative to project root (specclaw_dir parent or repo root)
    if [[ "$fp" = /* ]]; then
      full_path="$fp"
    else
      # Try relative to specclaw_dir first, then cwd
      if [ -f "${specclaw_dir}/${fp}" ]; then
        full_path="${specclaw_dir}/${fp}"
      elif [ -f "$fp" ]; then
        full_path="$fp"
      else
        full_path="${specclaw_dir}/${fp}"
      fi
    fi

    [ -n "$files_json" ] && files_json="${files_json},"

    if [ -f "$full_path" ]; then
      local content
      local total_lines
      total_lines=$(wc -l < "$full_path")
      content=$(head -200 "$full_path")
      if [ "$total_lines" -gt 200 ]; then
        content="${content}
... (truncated, ${total_lines} total lines)"
      fi
      files_json="${files_json}
    {\"path\": \"$(json_escape "$fp")\", \"exists\": true, \"content\": \"$(json_escape "$content")\"}"
    else
      files_json="${files_json}
    {\"path\": \"$(json_escape "$fp")\", \"exists\": false, \"content\": null}"
    fi
  done

  # 4. Read config for commands
  local test_cmd="" lint_cmd="" build_cmd=""
  if [ -f "$config_file" ]; then
    test_cmd=$(yaml_val "$config_file" "build.test_command")
    lint_cmd=$(yaml_val "$config_file" "build.lint_command")
    build_cmd=$(yaml_val "$config_file" "build.build_command")
  else
    warn "config.yaml not found at ${config_file}, skipping commands"
  fi

  # 5. Run commands
  local test_output="" lint_output="" build_output=""
  local tests_passed=true lint_passed=true build_passed=true

  if [ -n "$test_cmd" ]; then
    if ! run_capped test_output "$test_cmd"; then
      tests_passed=false
    fi
  fi

  if [ -n "$lint_cmd" ]; then
    if ! run_capped lint_output "$lint_cmd"; then
      lint_passed=false
    fi
  fi

  if [ -n "$build_cmd" ]; then
    if ! run_capped build_output "$build_cmd"; then
      build_passed=false
    fi
  fi

  # 6. Build AC JSON array
  local ac_json=""
  for ac in "${ac_lines[@]}"; do
    [ -n "$ac_json" ] && ac_json="${ac_json},"
    ac_json="${ac_json}
    \"$(json_escape "$ac")\""
  done

  # 7. Output JSON
  local output
  output=$(cat <<ENDJSON
{
  "change": "$(json_escape "$change_name")",
  "acceptance_criteria": [${ac_json}
  ],
  "changed_files": [${files_json}
  ],
  "test_output": "$(json_escape "$test_output")",
  "lint_output": "$(json_escape "$lint_output")",
  "build_output": "$(json_escape "$build_output")",
  "tests_passed": ${tests_passed},
  "lint_passed": ${lint_passed},
  "build_passed": ${build_passed}
}
ENDJSON
)

  # 8. Validate with jq if available
  if command -v jq &>/dev/null; then
    if printf '%s' "$output" | jq . >/dev/null 2>&1; then
      printf '%s\n' "$output"
    else
      warn "JSON validation failed, outputting best-effort"
      printf '%s\n' "$output"
    fi
  else
    printf '%s\n' "$output"
  fi
}

# ─── Subcommand: report ──────────────────────────────────────────────────────

cmd_report() {
  local specclaw_dir="$1"
  local change_name="$2"
  local change_dir="${specclaw_dir}/changes/${change_name}"
  local report_file="${change_dir}/verify-report.md"

  [ -f "$report_file" ] || die "verify-report.md not found at ${report_file}"

  # Extract verdict line (look for Verdict: or **Verdict:**)
  local verdict
  verdict=$(grep -iE '(verdict|overall)[[:space:]]*:' "$report_file" | head -1 | sed 's/^.*:[[:space:]]*//' | sed 's/\*//g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  [ -z "$verdict" ] && verdict="UNKNOWN"

  # Normalize verdict
  local norm_verdict="UNKNOWN"
  case "$(printf '%s' "$verdict" | tr '[:upper:]' '[:lower:]')" in
    *pass*) norm_verdict="PASS" ;;
    *fail*) norm_verdict="FAIL" ;;
    *partial*) norm_verdict="PARTIAL" ;;
    *) norm_verdict="$verdict" ;;
  esac

  # Count pass/fail from checklist items
  local total=0 passed=0
  while IFS= read -r line; do
    total=$((total + 1))
    if printf '%s' "$line" | grep -qE '^\s*- \[x\]'; then
      passed=$((passed + 1))
    fi
  done < <(grep -E '^\s*- \[(x| )\]' "$report_file" || true)

  local issues=$((total - passed))

  echo "Verdict: ${norm_verdict}"
  echo "Passed: ${passed}/${total}"
  echo "Issues: ${issues}"
}

# ─── Subcommand: update-status ───────────────────────────────────────────────

cmd_update_status() {
  local specclaw_dir="$1"
  local change_name="$2"
  local verdict="$3"
  local change_dir="${specclaw_dir}/changes/${change_name}"
  local status_file="${change_dir}/status.md"

  [ -f "$status_file" ] || die "status.md not found at ${status_file}"

  # Determine status emoji
  local status_text
  case "$(printf '%s' "$verdict" | tr '[:upper:]' '[:lower:]')" in
    pass)    status_text="✅ Passed" ;;
    fail)    status_text="❌ Failed" ;;
    partial) status_text="⚠️ Partial" ;;
    *)       die "Invalid verdict: ${verdict}. Must be PASS, FAIL, or PARTIAL" ;;
  esac

  # Check if Verify row exists in the table
  if grep -qE '^\|[[:space:]]*Verify[[:space:]]*\|' "$status_file"; then
    # Update existing Verify row — replace the status column
    local tmpfile
    tmpfile=$(mktemp)
    while IFS= read -r line; do
      if printf '%s' "$line" | grep -qE '^\|[[:space:]]*Verify[[:space:]]*\|'; then
        # Rebuild the row preserving the Notes column
        local notes
        notes=$(printf '%s' "$line" | awk -F'|' '{print $4}' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        printf '| Verify | %s | %s |\n' "$status_text" "$notes"
      else
        printf '%s\n' "$line"
      fi
    done < "$status_file" > "$tmpfile"
    mv "$tmpfile" "$status_file"
  else
    # Append a Verify row — find the table and add after the last row
    # Or just append if we can't find the table
    local tmpfile
    tmpfile=$(mktemp)
    local in_table=false table_ended=false appended=false
    while IFS= read -r line; do
      printf '%s\n' "$line"
      # Detect table rows (lines starting with |)
      if printf '%s' "$line" | grep -qE '^\|.*(Phase|Build|Tasks|Design|Spec|Proposal).*\|'; then
        in_table=true
      elif $in_table && ! printf '%s' "$line" | grep -qE '^\|'; then
        # Table ended, insert Verify row before this line
        if ! $appended; then
          printf '| Verify | %s |  |\n' "$status_text"
          appended=true
        fi
        in_table=false
      fi
    done < "$status_file" > "$tmpfile"
    # If we never left the table (file ends with table), append
    if ! $appended; then
      printf '| Verify | %s |  |\n' "$status_text" >> "$tmpfile"
    fi
    mv "$tmpfile" "$status_file"
  fi

  echo "Updated status.md: Verify → ${status_text}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  collect)
    [ $# -ge 3 ] || die "Usage: verify.sh collect <specclaw_dir> <change_name>"
    cmd_collect "$2" "$3"
    ;;
  report)
    [ $# -ge 3 ] || die "Usage: verify.sh report <specclaw_dir> <change_name>"
    cmd_report "$2" "$3"
    ;;
  update-status)
    [ $# -ge 4 ] || die "Usage: verify.sh update-status <specclaw_dir> <change_name> <verdict>"
    cmd_update_status "$2" "$3" "$4"
    ;;
  "")
    usage
    exit 1
    ;;
  *)
    die "Unknown subcommand: $1. Run verify.sh --help for usage."
    ;;
esac
