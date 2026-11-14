# shellcheck shell=bash
# lib/plugins.sh — the add-on install check, shared by hooks/session-start and
# specclaw-suggest (change 059). Sourced, never executed. Callers set PLUGIN_ROOT.

# installed <command> <plugin> — the add-on counts as installed when its command
# is on PATH, or when it sits next to this plugin: plugins/<name>/bin in a
# checkout, <cache>/<owner>/<name>/<ver>/bin in the plugin cache. The second
# check covers hook environments without plugin bin/ dirs on PATH.
installed() {
  command -v "$1" >/dev/null 2>&1 \
    || compgen -G "$PLUGIN_ROOT/../$2/bin/$1" >/dev/null \
    || compgen -G "$PLUGIN_ROOT/../../$2/*/bin/$1" >/dev/null
}

# missing <feature text> <command> <plugin> — append one install line to NOTICE.
missing() { installed "$2" "$3" || NOTICE="${NOTICE}
- This project uses $1, but the $3 plugin is not installed: /plugin install $3@chan4lk"; }
