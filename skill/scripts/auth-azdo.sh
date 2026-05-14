#!/usr/bin/env bash
# auth-azdo.sh — Interactive Azure DevOps auth setup
# Guides user to PAT creation page, validates token, saves to .specclaw/.env + config.yaml
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: auth-azdo.sh <specclaw_dir>

Set up Azure DevOps authentication for specclaw. Guides you to:
  1. Enter org + project + repo names
  2. Open the PAT creation page in your browser
  3. Paste the generated token
  4. Validates and saves credentials

Arguments:
  specclaw_dir   Path to the .specclaw directory
EOF
  exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

if [[ $# -lt 1 ]]; then
  echo "ERROR: Expected argument: <specclaw_dir>" >&2
  exit 1
fi

SPECCLAW_DIR="$1"
CONFIG_FILE="$SPECCLAW_DIR/config.yaml"
AUTH_FILE="$SPECCLAW_DIR/.env"

[[ -d "$SPECCLAW_DIR" ]] || { echo "ERROR: specclaw directory not found: $SPECCLAW_DIR" >&2; exit 1; }
[[ -f "$CONFIG_FILE" ]]  || { echo "ERROR: config.yaml not found — run: specclaw init" >&2; exit 1; }

die() { echo "ERROR: $*" >&2; exit 1; }

# ─── Helpers ──────────────────────────────────────────────────────────────────

env_set() {
  local key="$1" val="$2"
  if [[ -f "$AUTH_FILE" ]] && grep -q "^${key}=" "$AUTH_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$AUTH_FILE"
  else
    echo "${key}=${val}" >> "$AUTH_FILE"
  fi
}

yaml_set_azdo() {
  local key="$1" val="$2"
  if grep -q '^azdo:' "$CONFIG_FILE" 2>/dev/null; then
    if grep -qE "^[[:space:]]+${key}:" "$CONFIG_FILE" 2>/dev/null; then
      sed -i "s|^\([[:space:]]*\)${key}:.*|\1${key}: \"${val}\"|" "$CONFIG_FILE"
    else
      sed -i "/^azdo:/a\\  ${key}: \"${val}\"" "$CONFIG_FILE"
    fi
  else
    printf '\n# Azure DevOps integration\nazdo:\n  enabled: true\n  org: ""\n  project: ""\n  repo: ""\n' >> "$CONFIG_FILE"
    yaml_set_azdo "$key" "$val"
  fi
}

ensure_gitignored() {
  local gitignore
  gitignore="$(cd "$SPECCLAW_DIR/.." && git rev-parse --show-toplevel 2>/dev/null)/.gitignore"
  if [[ -f "$gitignore" ]] && ! grep -q '\.specclaw/\.env' "$gitignore" 2>/dev/null; then
    echo ".specclaw/.env" >> "$gitignore"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "SpecClaw — Azure DevOps Auth Setup"
  echo "===================================="
  echo ""

  echo -n "Azure DevOps org name (part after dev.azure.com/ — e.g. 'mycompany'): "
  read -r ORG </dev/tty
  [[ -n "$ORG" ]] || die "Org name required"

  echo -n "Project name (e.g. 'MyProject'): "
  read -r PROJECT </dev/tty
  [[ -n "$PROJECT" ]] || die "Project name required"

  echo -n "Repository name (e.g. 'my-repo'): "
  read -r REPO </dev/tty
  [[ -n "$REPO" ]] || die "Repository name required"

  echo ""
  echo "─────────────────────────────────────────────────────────────────"
  echo "Now create a Personal Access Token:"
  echo ""
  echo "  Open → https://dev.azure.com/${ORG}/_usersSettings/tokens"
  echo ""
  echo "  Token settings:"
  echo "    Name:        specclaw (or any label)"
  echo "    Expiration:  90 days recommended"
  echo "    Scopes:      Custom defined"
  echo "      ✓ Code          → Read & Write"
  echo "      ✓ Work Items    → Read & Write"
  echo "      (Pull Requests are covered under Code scope)"
  echo ""
  echo "  Click 'Create' then copy the token shown."
  echo "─────────────────────────────────────────────────────────────────"
  echo ""
  echo -n "Paste your PAT here (hidden): "
  read -rs TOKEN </dev/tty
  echo ""
  [[ -n "$TOKEN" ]] || die "Token required"

  echo "Validating..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u ":${TOKEN}" \
    "https://dev.azure.com/${ORG}/_apis/projects/${PROJECT}?api-version=7.1") || true

  case "$HTTP_CODE" in
    200) echo "✅ Token valid — project '${PROJECT}' confirmed" ;;
    401) die "Token invalid or expired — check scopes and try again" ;;
    404) die "Project '${PROJECT}' not found in org '${ORG}' — check names" ;;
    *)   die "Validation failed (HTTP ${HTTP_CODE}) — check org/project and token" ;;
  esac

  yaml_set_azdo "enabled" "true"
  yaml_set_azdo "org"     "$ORG"
  yaml_set_azdo "project" "$PROJECT"
  yaml_set_azdo "repo"    "$REPO"

  env_set "AZDO_TOKEN"   "$TOKEN"
  env_set "AZDO_ORG"     "$ORG"
  env_set "AZDO_PROJECT" "$PROJECT"
  env_set "AZDO_REPO"    "$REPO"

  ensure_gitignored

  echo ""
  echo "✅ Azure DevOps auth saved."
  echo "   Org:     $ORG"
  echo "   Project: $PROJECT"
  echo "   Repo:    $REPO"
  echo "   Token:   stored in ${AUTH_FILE} (gitignored)"
  echo ""
  echo "Next: 'specclaw pr <change>' to create an ADO pull request."
}

main
