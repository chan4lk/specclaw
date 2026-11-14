# shellcheck shell=bash
# lib/plugins.sh — the add-on plugin table and install check, shared by
# hooks/session-start and specclaw-suggest (change 059). Sourced, never executed.
# Callers set PLUGIN_ROOT (this plugin's root) and CONFIG (config.yaml).

# plugin_feature <feature> — "<command it ships>|<plugin>|<what it adds>".
plugin_feature() {
  case "$1" in
    review) echo "specclaw-review|specclaw-review|a review loop checks each change against your project's rules before its PR" ;;
    fleet)  echo "specclaw-fleet|specclaw-fleet|run approved changes in parallel as headless jobs" ;;
    sync)   echo "specclaw-gh-sync|specclaw-sync|keep changes in step with GitHub issues, Azure Boards or Jira" ;;
    bf)     echo "specclaw-bf-status|specclaw-bf|brownfield analysis maps an existing codebase before you change it" ;;
    extras) echo "specclaw-party|specclaw-extras|the review panel and automation" ;;
    *) return 1 ;;
  esac
}

# plugins_dismissed — the features in config.yaml `plugins.dismissed`, space-separated.
# Reads an inline list (`dismissed: [a, b]`) and a block list (`- a` lines under it). The list ends at
# the next key; blank and comment lines inside it do not end it. specclaw-suggest --dismiss uses the same rule.
plugins_dismissed() {
  awk '
    /^[a-zA-Z_]/ { inblk = ($0 ~ /^plugins:/); inlist = 0; next }
    !inblk { next }
    /^  dismissed:/ { v = $0; sub(/^  dismissed:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v); out = out " " v; inlist = 1; next }
    inlist && /^[[:space:]]+-[[:space:]]/ { v = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v); out = out " " v; next }
    /^  [a-zA-Z_]/ { inlist = 0 }
    END { gsub(/[][,"'"'"']/, " ", out); print out }
  ' "$CONFIG" 2>/dev/null | xargs
}

plugin_dismissed() { case " $(plugins_dismissed) " in *" $1 "*) return 0 ;; esac; return 1; }

# installed <command> <plugin> — the add-on counts as installed when its command
# is on PATH, or when it sits next to this plugin: plugins/<name>/bin in a
# checkout, <cache>/<owner>/<name>/<ver>/bin in the plugin cache. The second
# check covers hook environments without plugin bin/ dirs on PATH.
installed() {
  command -v "$1" >/dev/null 2>&1 \
    || compgen -G "$PLUGIN_ROOT/../$2/bin/$1" >/dev/null \
    || compgen -G "$PLUGIN_ROOT/../../$2/*/bin/$1" >/dev/null
}

# missing <what the project uses> <feature> — append one install line to NOTICE,
# unless the plugin is installed or the user dismissed the feature.
missing() {
  local spec cmd plugin
  spec="$(plugin_feature "$2")" || return 0
  IFS='|' read -r cmd plugin _ <<<"$spec"
  installed "$cmd" "$plugin" || plugin_dismissed "$2" || NOTICE="${NOTICE}
- This project uses $1, but the $plugin plugin is not installed: /plugin install $plugin@chan4lk"
}
