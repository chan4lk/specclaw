# shellcheck shell=bash
# quality-scan.sh — the measurement core shared by specclaw-quality-scan and
# specclaw-bf-quality-collect (change 042): config reading, thresholds, scan
# exclusions, file enumeration and the scc / lizard / jscpd runners. Sourced,
# never executed. Callers define warn() and die() before sourcing it.

# ─── JSON helpers ─────────────────────────────────────────────────────────────

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ─── config.yaml reader (copied verbatim from specclaw-bf-rebuild-collect) ────

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

  if [[ "$value" =~ ([[:space:]]+#) ]]; then
    value="${value%%"${BASH_REMATCH[1]}"*}"
  fi
  if [[ "$value" =~ [[:space:]]+$ ]]; then
    value="${value%"${BASH_REMATCH[0]}"}"
  fi
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

# ─── capability_table ────────────────────────────────────────────────────────
#
# DATA, not logic. Columns:
#
#   extension <TAB> language <TAB> scc <TAB> lizard <TAB> jscpd
#
# where each tool column is 1 when that tool parses this language and 0 when it
# does not. A 0 is what produces language_unsupported, which is why the table is
# the honest core of this script rather than a convenience: getting a row wrong
# means claiming a measurement nobody made, or withholding one that exists.
#
# An extension absent from the table is out of scope for every metric and is
# counted under the "unclassified" file count — never silently folded into a
# language it might be.
capability_table() {
  cat <<'CAPTABLE'
.cs	C#	1	1	1
.vb	Visual Basic	1	0	1
.java	Java	1	1	1
.kt	Kotlin	1	1	1
.kts	Kotlin	1	1	1
.js	JavaScript	1	1	1
.jsx	JavaScript	1	1	1
.mjs	JavaScript	1	1	1
.cjs	JavaScript	1	1	1
.ts	TypeScript	1	1	1
.tsx	TypeScript	1	1	1
.py	Python	1	1	1
.rb	Ruby	1	1	1
.go	Go	1	1	1
.rs	Rust	1	1	1
.php	PHP	1	1	1
.swift	Swift	1	1	1
.scala	Scala	1	1	1
.lua	Lua	1	1	1
.pl	Perl	1	1	0
.pm	Perl	1	1	0
.c	C	1	1	1
.h	C	1	1	1
.cpp	C++	1	1	1
.cc	C++	1	1	1
.cxx	C++	1	1	1
.hpp	C++	1	1	1
.m	Objective-C	1	1	1
.mm	Objective-C	1	1	1
.erl	Erlang	1	1	0
.zig	Zig	1	1	0
.sol	Solidity	1	1	0
.pas	Pascal	1	0	1
.pp	Pascal	1	0	1
.dpr	Pascal	1	0	1
.dpk	Pascal	1	0	1
.sql	SQL	1	0	1
.sh	Shell	1	0	0
.bash	Shell	1	0	0
.ps1	PowerShell	1	0	0
CAPTABLE
}

# ─── threshold defaults ──────────────────────────────────────────────────────
#
# THE ONLY PLACE A THRESHOLD NUMBER IS WRITTEN. Every one of these is
# overridable from .specclaw/config.yaml's `quality:` block, and they reach the
# classification logic as jq --argjson values, so no comparison anywhere below
# contains a literal. Changing a policy is a config edit, never a code edit.
#
# register_severity is the one non-numeric knob: which severity band earns a
# permanent QI-### id. It defaults to HIGH deliberately. QI ids are permanent
# and entries are never deleted, so a registry that admitted every WARN on a
# large legacy tree would grow to thousands of rows that outlive the code they
# describe. WARN findings are still counted in every module rollup — they are
# just not individually immortalised.
load_thresholds() {
  local config_file="$1"
  local -A t=(
    [complexity_warn]=10
    [complexity_high]=20
    [function_length_warn]=60
    [function_length_high]=120
    [duplication_warn]=5
    [duplication_high]=15
    [file_length_warn]=500
    [file_length_high]=1000
    # Clone knobs that CHANGE A VERDICT, and only those. A clone at or above
    # clone_qi_min_lines earns a permanent QI-###; clone_function_min_overlap
    # decides whether a function name may be attached to a clone side. Both
    # belong here because --compare checks the thresholds block, and two
    # snapshots classified against different values of either are answering
    # different questions.
    #
    # The two presentation caps — how many clones the artifact stores and how
    # many the report shows — are deliberately NOT here. They change no
    # classification, and putting them here would make raising the report's
    # top-M emit a spurious "different thresholds" warning on the next compare.
    [clone_qi_min_lines]=30
    [clone_function_min_overlap]=0.5
  )
  local register_severity="HIGH"
  local k v
  if [ -f "$config_file" ]; then
    for k in "${!t[@]}"; do
      v="$(yaml_val "$config_file" "quality.${k}")"
      if [ -n "$v" ] && [[ "$v" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        t[$k]="$v"
      elif [ -n "$v" ]; then
        warn "config.yaml quality.${k} is not a number ('${v}') — using the default ${t[$k]}."
      fi
    done
    v="$(yaml_val "$config_file" "quality.register_severity")"
    case "$(printf '%s' "${v:-}" | tr '[:lower:]' '[:upper:]')" in
      HIGH) register_severity="HIGH" ;;
      WARN) register_severity="WARN" ;;
      "") : ;;
      *) warn "config.yaml quality.register_severity must be HIGH or WARN ('${v}') — using HIGH." ;;
    esac
  fi

  printf '{'
  local first=true
  for k in complexity_warn complexity_high function_length_warn function_length_high \
           duplication_warn duplication_high file_length_warn file_length_high \
           clone_qi_min_lines clone_function_min_overlap; do
    if $first; then first=false; else printf ','; fi
    printf '"%s":%s' "$k" "${t[$k]}"
  done
  printf ',"register_severity":"%s"}' "$register_severity"
}


# ─── scan exclusions ─────────────────────────────────────────────────────────
#
# EXCLUSIONS ARE CONFIG, EXACTLY LIKE THRESHOLDS. Not one pattern appears in
# this script. The defaults ship as data in lib/quality-exclusions.yaml and the
# project layer overlays them from .specclaw/config.yaml's
# `quality.exclusions:` block; both files use the identical
# `quality:` -> `exclusions:` nesting so one parser reads both. Everything below
# consumes that data — it never decides what a build directory is called.
#
# WHY THE DEFAULTS ARE NOT IN THIS FILE. A default set living here would be a
# policy hardcoded in the thing the policy governs, and the whole point of
# threshold config was to stop exactly that. Nor can they live only in
# templates/config.yaml, which is copied once at init: every project initialised
# before this existed would silently start measuring its dependencies.
#
# WHY THE DEFAULTS ARE NOT OPTIONAL. A missing defaults file is an installation
# fault, not a configuration choice, and the failure it produces is silent
# (every dependency measured, every number quietly wrong). So it warns loudly
# and measures everything, rather than pretending a scope nobody chose.
#
# The category order below is the CENSUS ATTRIBUTION ORDER: a file matching two
# categories is counted under the first one listed, deterministically, so two
# runs over the same tree produce the same census. It is not a precedence rule
# about whether the file is excluded — one match anywhere excludes it.
EXCLUSION_CATEGORIES="generated third_party_and_build tests pipeline_owned data_and_lockfiles"

# read_exclusion_block <yaml_file> — the one parser for both layers.
#
# yaml_val cannot do this job: it reads a flat `section.field` SCALAR and this
# block is three levels deep and mostly lists. Rather than teach that function
# nesting it does not need anywhere else, this reads the one shape it must and
# emits normalised rows:
#
#   L <TAB> <key> <TAB> <item>    a list item under <key>
#   S <TAB> <key> <TAB> <value>   a scalar value for <key>
#   E <TAB> <key> <TAB>           <key> present as an explicitly empty list
#
# The E row matters: `extra_excludes: []` in a project's config is a statement
# ("I have none"), and it must be distinguishable from the key being absent so
# an overlay can tell "unset, inherit" from "set to nothing".
read_exclusion_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    function ind(s,   i) { i = match(s, /[^ ]/); return (i == 0 ? -1 : i - 1) }
    # Values may be quoted (patterns carry * and #, which YAML would otherwise
    # read as a comment) or bare with a trailing inline comment. Take the quoted
    # span when there is one, strip an inline comment when there is not.
    function val(v) {
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (substr(v, 1, 1) == "\"") { sub(/^"/, "", v); sub(/".*$/, "", v); return v }
      if (substr(v, 1, 1) == "'\''") { sub(/^'\''/, "", v); sub(/'\''.*$/, "", v); return v }
      sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
      return v
    }
    { line = $0; sub(/\r$/, "", line) }
    line ~ /^[[:space:]]*#/ { next }
    line ~ /^[[:space:]]*$/ { next }
    {
      i = ind(line); body = line; sub(/^ */, "", body)
      if (i == 0) { inq = (body ~ /^quality:/); inx = 0; key = ""; next }
      if (!inq) next
      if (i == 2) { inx = (body ~ /^exclusions:[[:space:]]*$/); key = ""; next }
      if (!inx) next
      if (i == 4 && body ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
        key = body; sub(/:.*$/, "", key)
        rest = body; sub(/^[A-Za-z_][A-Za-z0-9_]*:/, "", rest); rest = val(rest)
        if (rest == "[]") { printf "E\t%s\t\n", key }
        else if (rest != "") { printf "S\t%s\t%s\n", key, rest }
        next
      }
      if (i >= 6 && body ~ /^- / && key != "") {
        item = body; sub(/^-[ \t]*/, "", item); item = val(item)
        if (item != "") printf "L\t%s\t%s\n", key, item
      }
    }
  ' "$file"
}

# is_true <value> — YAML truthiness, restricted deliberately. Anything that is
# not recognisably true or false is a typo, and a typo that silently reads as
# "off" turns the whole scan scope into something nobody chose.
excl_flag() {
  local raw="$1" default="$2" label="$3"
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
    "")             printf '%s' "$default" ;;
    true|yes|on|1)  printf 'true' ;;
    false|no|off|0) printf 'false' ;;
    *) warn "config.yaml quality.exclusions.${label} must be true or false ('${raw}') — using the default ${default}."
       printf '%s' "$default" ;;
  esac
}

# build_exclusion_set <defaults_yaml> <config_yaml> <out_patterns_tsv> <out_effective>
#
# Overlays the project layer on the defaults and writes two artifacts:
#
#   out_patterns_tsv   category <TAB> pattern, in census-attribution order,
#                      with include_overrides carried as the reserved category
#                      __include__. This is the filter's whole input.
#   out_effective      the same content in a canonical, order-stable form. It is
#                      what gets hashed into exclusions.config_hash, so two runs
#                      agree iff they measured the same scope.
#
# Echoes a JSON object describing the effective config, for the artifact.
build_exclusion_set() {
  local defaults="$1" config="$2" out_tsv="$3" out_eff="$4"
  : > "$out_tsv"; : > "$out_eff"

  local dflt proj
  dflt="$(mktemp)"; proj="$(mktemp)"
  read_exclusion_block "$defaults" > "$dflt"
  read_exclusion_block "$config"   > "$proj"

  # Toggles: the project layer's scalar for a category, defaulting to on. A
  # category switched off keeps its patterns in the defaults file — flipping it
  # back on restores them, so turning one off is never a deletion.
  local cat enabled raw praw json_cats="" n_pat sep=""
  local bucket_raw bucket
  bucket_raw="$(awk -F'\t' '$1 == "S" && $2 == "tests_as_separate_bucket" {print $3; exit}' "$proj")"
  bucket="$(excl_flag "$bucket_raw" "false" "tests_as_separate_bucket")"

  for cat in $EXCLUSION_CATEGORIES; do
    # Default first, then the project layer over it. Read as two separate
    # lookups rather than one awk over both files: the overlay must be visible
    # as an overlay, and "whichever file awk hit first" is not the same rule.
    raw="$(awk -F'\t' -v k="$cat" '$1 == "S" && $2 == k {print $3; exit}' "$dflt")"
    praw="$(awk -F'\t' -v k="$cat" '$1 == "S" && $2 == k {print $3; exit}' "$proj")"
    [ -z "$praw" ] || raw="$praw"
    enabled="$(excl_flag "$raw" "true" "$cat")"
    n_pat=0
    if [ "$enabled" = "true" ]; then
      while IFS= read -r raw; do
        [ -n "$raw" ] || continue
        printf '%s\t%s\n' "$cat" "$raw" >> "$out_tsv"
        n_pat=$((n_pat + 1))
      done < <(awk -F'\t' -v k="$cat" '$1 == "L" && $2 == k {print $3}' "$dflt")
    fi
    json_cats="${json_cats}${sep}$(printf '"%s":{"enabled":%s,"patterns":%s}' \
      "$(json_escape "$cat")" "$enabled" "$n_pat")"
    sep=","
  done

  # extra_excludes and include_overrides come from the PROJECT layer only. A
  # default that named one project's directories would not be stack-blind, which
  # is why lib/quality-exclusions.yaml ships them empty.
  local extras_json="" overrides_json="" esep=""
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    printf 'extra_excludes\t%s\n' "$raw" >> "$out_tsv"
    extras_json="${extras_json}${esep}\"$(json_escape "$raw")\""; esep=","
  done < <(awk -F'\t' '$1 == "L" && $2 == "extra_excludes" {print $3}' "$proj")
  esep=""
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    printf '__include__\t%s\n' "$raw" >> "$out_tsv"
    overrides_json="${overrides_json}${esep}\"$(json_escape "$raw")\""; esep=","
  done < <(awk -F'\t' '$1 == "L" && $2 == "include_overrides" {print $3}' "$proj")

  # The hashed form. Sorted, so the hash depends on WHAT is excluded and not on
  # the order two equivalent config files happened to list it in — otherwise
  # reordering a list would stop a legitimate comparison for no reason.
  {
    printf 'tests_as_separate_bucket\t%s\n' "$bucket"
    LC_ALL=C sort "$out_tsv"
  } > "$out_eff"

  rm -f "$dflt" "$proj"
  printf '{"categories":{%s},"extra_excludes":[%s],"include_overrides":[%s],"tests_as_separate_bucket":%s}' \
    "$json_cats" "$extras_json" "$overrides_json" "$bucket"
}

# scope_hash <effective_file> — identity of the measured scope (PD-04).
#
# Follows the sha256: convention specclaw-bf-baseline and specclaw-bf-ui already
# use, with their fallback ladder. When nothing can hash, the value is the
# literal "unhashable" — which compare treats as a mismatch against everything
# INCLUDING another "unhashable", because two scopes nobody could identify are
# not two scopes anyone showed to be the same.
scope_hash() {
  local f="$1" h=""
  if command -v sha256sum >/dev/null 2>&1; then
    h="$(sha256sum "$f" 2>/dev/null | awk '{print $1}' || true)"
  elif command -v shasum >/dev/null 2>&1; then
    h="$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}' || true)"
  elif command -v openssl >/dev/null 2>&1; then
    h="$(openssl dgst -sha256 "$f" 2>/dev/null | awk '{print $NF}' || true)"
  fi
  if [ -n "$h" ]; then printf 'sha256:%s' "$h"; else printf 'unhashable'; fi
}

# apply_exclusions <patterns_tsv> <all_paths> <out_kept> <out_census_tsv>
#
# ONE PASS, ONE MEASURED LIST (PD-02). Every downstream consumer — scc, lizard,
# jscpd, the module join, the aggregation — reads the list this produces. The
# tools' own ignore flags are generated from the same data further down, but
# they are a walking-speed optimisation and never the mechanism: three tools
# with three ignore syntaxes drift, and a duplication percentage computed over a
# different denominator than the complexity scan silently corrupts every module
# rollup that combines them.
#
# Matching semantics are defined once, in lib/quality-exclusions.yaml's header,
# and implemented once, here. Globs compile to EREs: `**/` -> `(.*/)?` so a
# pattern anchored at any depth also matches at the root, `**` -> `.*` crossing
# separators, `*` -> `[^/]*` which does not, `?` -> `[^/]`. Both the pattern and
# the path are lower-cased, because a repo that has been through a Windows
# checkout carries both Migrations/ and migrations/ and excluding only one
# produces a number that is wrong and still looks plausible.
#
# An include_overrides match always wins, and it is tested only after an
# exclusion matched — an override cannot exclude anything, only rescue.
#
# Whitespace-safe by construction: awk reads whole lines and the kept list is
# written line-per-path, never through word-splitting or argv.
apply_exclusions() {
  local patterns="$1" all="$2" kept="$3" census="$4"
  : > "$kept"; : > "$census"
  if [ ! -s "$patterns" ]; then
    cp "$all" "$kept"
    return 0
  fi
  awk -F'\t' -v CENSUS="$census" '
    function g2e(g,   s, o, i, ch) {
      s = tolower(g); o = "^"; i = 1
      while (i <= length(s)) {
        ch = substr(s, i, 1)
        if (ch == "*") {
          if (substr(s, i, 3) == "**/") { o = o "(.*/)?"; i += 3; continue }
          if (substr(s, i, 2) == "**")  { o = o ".*";     i += 2; continue }
          o = o "[^/]*"; i += 1; continue
        }
        if (ch == "?") { o = o "[^/]"; i += 1; continue }
        if (index(".+()[]{}^$|\\", ch) > 0) { o = o "\\" ch; i += 1; continue }
        o = o ch; i += 1
      }
      return o "$"
    }
    NR == FNR {
      if ($1 == "__include__") { inc[++ni] = g2e($2) }
      else { cat[++np] = $1; pat[np] = g2e($2) }
      next
    }
    {
      if ($0 == "") next
      p = tolower($0); hit = ""
      for (i = 1; i <= np; i++) if (p ~ pat[i]) { hit = cat[i]; break }
      if (hit != "") for (i = 1; i <= ni; i++) if (p ~ inc[i]) { hit = ""; break }
      if (hit == "") print $0
      else printf "%s\t%s\n", hit, $0 >> CENSUS
    }
  ' "$patterns" "$all" > "$kept"
}

# excl_dir_names <patterns_tsv> — the bare directory names among the effective
# patterns, for the metric tools that take names rather than globs.
#
# Only `**/NAME/**` yields a name; a pattern of any other shape is left to the
# intersection. This feeds TOOL FLAGS ONLY and never file enumeration: a tool
# that skips a directory saves a parse, whereas an enumerator that skips one
# loses a census row. .git is added unconditionally and is the one path named
# here rather than configured — it is the repository's own metadata, not a
# scoping policy, and nothing in it was ever going to be reported.
excl_dir_names() {
  local patterns="$1"
  { printf '.git\n'
    awk -F'\t' '$1 != "__include__" && $2 ~ /^\*\*\/[^*\/]+\/\*\*$/ {
      n = $2; sub(/^\*\*\//, "", n); sub(/\/\*\*$/, "", n); print n
    }' "$patterns"
  } | awk '!seen[$0]++' | paste -sd, - | tr -d '\n'
}

# excl_globs <patterns_tsv> — every effective exclude pattern, comma-joined, for
# a tool whose ignore flag speaks ** globs natively. A pattern containing a
# comma cannot survive a comma-joined flag and is dropped here rather than
# corrupting the ones around it; the intersection still excludes its files.
excl_globs() {
  local patterns="$1"
  awk -F'\t' '$1 != "__include__" && index($2, ",") == 0 {print $2}' "$patterns" \
    | awk '!seen[$0]++' | paste -sd, - | tr -d '\n'
}

# ─── tool probe (PD-09) ──────────────────────────────────────────────────────

have_tool() { command -v "$1" >/dev/null 2>&1; }

# ─── file enumeration ────────────────────────────────────────────────────────
#
# Mirrors specclaw-bf-analyze-codebase's convention: git ls-files when inside a
# work tree, a pruning find otherwise. `git ls-files` happily lists a committed
# vendor/ or node_modules/ tree, so neither source is trusted to have scoped
# itself — this produces the RAW list and apply_exclusions scopes it.
#
# THE FIND FALLBACK PRUNES ONLY .git, AND THAT IS DELIBERATE. An earlier version
# pruned every excluded directory here as a walking-speed optimisation, and it
# was wrong for a reason worth recording: a pruned tree never reaches the filter,
# so its files are never COUNTED, and the census silently under-reports exactly
# the directories exclusion exists for. `node_modules: 0 files` when there are
# forty thousand is a worse artifact than a slower run. Excluding a file and
# hiding that you excluded it are different things, and only the first one is
# this feature.
#
# .git is the one exception and is not a scoping decision: it is the
# repository's own metadata, `git ls-files` never lists it on the other branch,
# and there is nothing there to report a count of. The cost this leaves on the
# table is a stat-only walk, not a parse — the metric tools still receive
# generated ignore flags, and that is where walking a dependency tree is
# actually expensive.
#
# The list this produces, once filtered, stays authoritative. Each metric tool
# is run over the scope directory and its output is then INTERSECTED with it,
# rather than trusting each tool's own ignore semantics to agree with ours.
# Three tools with three different ignore syntaxes would otherwise give three
# different denominators for the same repo.
enumerate_files() {
  local project_root="$1" rel_scope="$2" out="$3"
  local tmp_all f
  tmp_all="$(mktemp)"

  if git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$project_root" ls-files -z 2>/dev/null | tr '\0' '\n' > "$tmp_all"
  else
    (
      cd "$project_root" || exit 0
      find . -name .git -prune -o -type f -print 2>/dev/null | sed 's|^\./||'
    ) > "$tmp_all"
  fi

  : > "$out"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ -z "$rel_scope" ]; then
      printf '%s\n' "$f" >> "$out"
    else
      case "$f" in
        "$rel_scope"|"$rel_scope"/*) printf '%s\n' "$f" >> "$out" ;;
      esac
    fi
  done < "$tmp_all"
  rm -f "$tmp_all"
}


# ─── metric collection ───────────────────────────────────────────────────────
#
# Every runner writes a TSV keyed by repo-relative path, intersected with the
# enumerated file list. Paths are normalised to forward slashes: a tool built
# for Windows may hand back backslashes, and a path that differs only by
# separator silently fails to join, which shows up as a plausible-looking
# smaller denominator rather than as an error.
#
# On Windows the raw separator is only half the story:
#   - scc emits native backslash paths, but run_scc serialises them through
#     jq's @tsv, which ESCAPES each backslash to "\\"; converting "\" -> "/"
#     then yields a doubled "//", so the collapse step below is what actually
#     lets an scc path join.
#   - lizard --csv wraps its location field in double quotes and prefixes it
#     with ".\", so the surrounding quotes and a leading "./" must both go.
#   - jq/tools on Windows can leave a trailing CR on the final field.
# Order matters: strip CR and quotes first, fold separators, THEN collapse and
# trim the leading "./".
norm_paths() {
  sed -e 's|\r$||' \
      -e 's|^"||' -e 's|"$||' \
      -e 's|\\|/|g' \
      -e 's|//*|/|g' \
      -e 's|^\./||'
}

# loc.tsv: relpath <TAB> lines <TAB> code
run_scc() {
  local project_root="$1" scope_arg="$2" files="$3" out="$4" dir_names="$5"
  : > "$out"
  local raw; raw="$(mktemp)"
  if ! ( cd "$project_root" && scc --by-file --format json \
            --exclude-dir "$dir_names" \
            "$scope_arg" ) > "$raw" 2>/dev/null; then
    rm -f "$raw"
    return 1
  fi
  jq -r '
    (if type == "array" then . else [.] end)
    | .[]? | .Files[]?
    | [ (.Location // .Filename // ""), (.Lines // 0), (.Code // 0) ]
    | @tsv
  ' "$raw" 2>/dev/null | norm_paths | LC_ALL=C sort -u > "$raw.norm" || { rm -f "$raw" "$raw.norm"; return 1; }
  LC_ALL=C sort -u "$files" > "$raw.files"
  LC_ALL=C join -t$'\t' -1 1 -2 1 "$raw.files" "$raw.norm" > "$out" || true
  rm -f "$raw" "$raw.norm" "$raw.files"
  return 0
}

# funcs.tsv: relpath <TAB> function <TAB> ccn <TAB> length <TAB> params
#            <TAB> start_line <TAB> end_line
#
# start/end are APPENDED, never inserted: the aggregation program reads these
# rows positionally as .[0]..[4], so a new column anywhere but the end would
# silently reassign every metric it reads.
#
# `function` is NORMALISED here and nowhere else — unquoted by the CSV parser as
# it reads the field, so every consumer downstream of this file sees the bare
# name. It is part of a QI key, so the boundary the value enters on is the only
# honest place to do that; a second unquoting further in would be a second
# opinion about what the name is.
run_lizard() {
  local project_root="$1" scope_arg="$2" files="$3" out="$4" dir_names="$5"
  : > "$out"
  local raw; raw="$(mktemp)"
  # -x flags are built from the SAME generated directory-name list scc gets, as
  # an array rather than an interpolated string so a name with a space survives.
  # Only directory names: lizard's -x is fnmatch, not ** globs, and a
  # mistranslated glob that silently matches nothing is worse than no flag —
  # these are a walking-speed optimisation and the intersection is the mechanism.
  local -a xargs=() name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    xargs+=("-x" "./${name}/*" "-x" "*/${name}/*")
  done < <(printf '%s' "$dir_names" | tr ',' '\n')
  # lizard exits non-zero when its own warning thresholds trip, which is not an
  # error here — we classify against our own config, not its defaults. Judge it
  # on whether it produced parseable rows instead.
  # ${xargs[@]+…}: an empty array under `set -u` is an unbound-variable error on
  # bash before 4.4, and this list is empty whenever every category is off.
  ( cd "$project_root" && lizard --csv ${xargs[@]+"${xargs[@]}"} "$scope_arg" ) > "$raw" 2>/dev/null || true
  [ -s "$raw" ] || { rm -f "$raw"; return 1; }
  # lizard --csv columns, all eleven:
  #   1 nloc  2 ccn  3 tokens  4 params  5 length  6 location
  #   7 file  8 function  9 long_name  10 start_line  11 end_line
  #
  # SPLIT ON QUOTED FIELDS, NOT ON COMMAS. Columns 6-9 are quoted and three of
  # them routinely CONTAIN commas, so `-F','` does not read this format — it
  # reads a shifted one. lizard_ext/csvoutput.py builds each row as
  #
  #   ",".join(str(field) for field in fields)
  #
  # with 6-9 wrapped in quotes and nothing escaped, because it pre-sanitises
  # instead: `name.replace('"', "'")`. So a quote can never appear INSIDE a
  # field, but a comma can, and does:
  #
  #   long_name  every parameter list of arity >= 2 — "Run( int a , int b )"
  #   function   C++ operator, and templated names — "P::operator ,"
  #   file       any path with a comma in it
  #
  # Under `-F','` a two-parameter function therefore shifted 10 and 11 off the
  # end and both arrived EMPTY, which the optional-range branch below read as
  # "this lizard build emits no line numbers" and passed on as a blank start —
  # the one thing assert_qi_identity refuses to register. Real lizard against
  # real code produced almost nothing but such rows, so the run did not degrade,
  # it stopped. Worse than the loss, one shape mislabelled: a row ending
  # `int b)",7` put the START line in the end field, past the e < s guard, which
  # cannot fire while s is empty.
  #
  # Fields 1-5 are numeric by contract. A row where they are not is a
  # parse_error for that row, never a silently coerced zero.
  #
  # 10 and 11 are read for the clone-to-function join and for QI identity, and
  # are still treated as OPTIONAL: a row that reaches 8 fields but no further is
  # a perfectly good complexity measurement, and losing it because a lizard
  # build stopped emitting line numbers would trade a metric for a nicety. Such
  # a row carries empty ranges and simply never matches a clone. What changed is
  # that a blank range now means the columns are ABSENT, not merely misread.
  #
  # Read at FIXED indices, never $NF: csv_output ends with `fields.extend(...)`,
  # so any -E extension carrying FUNCTION_INFO (lizardnd, lizardio, halstead and
  # six more) appends its own columns AFTER end, and a row can legitimately
  # arrive wider than eleven.
  #
  # csv_split also UNQUOTES, which is where the function name loses the quotes
  # it used to carry all the way into a QI key. One normalisation, at the
  # boundary the value enters on. It honours "" as an escaped quote even though
  # this producer cannot emit one, so the parser is a CSV parser and not a
  # transcription of one tool's current habits.
  #
  # POSIX awk only — no FPAT, no gensub. This is the only awk in the collector
  # and gawk is not otherwise required, so requiring it here would be a new
  # dependency for a job substr can do. No `delete` either: indices above nf are
  # never read, so a wider previous row cannot leak into a narrower one.
  awk -v OFS='\t' '
    function csv_split(line, out,   n, i, c, nx, cur, inq) {
      n = 1; cur = ""; inq = 0
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (inq) {
          if (c == "\"") {
            nx = substr(line, i + 1, 1)
            if (nx == "\"") { cur = cur "\""; i++ } else { inq = 0 }
          } else { cur = cur c }
        } else if (c == "\"") { inq = 1 }
        else if (c == ",") { out[n++] = cur; cur = "" }
        else { cur = cur c }
      }
      out[n] = cur
      return n
    }
    {
      nf = csv_split($0, f)
      if (nf < 8) next
      if (f[1] !~ /^[0-9]+$/ || f[2] !~ /^[0-9]+$/) next
      if (f[4] !~ /^[0-9]+$/ || f[5] !~ /^[0-9]+$/) next
      # THE FILE-SCOPE PSEUDO-FUNCTION IS NOT A FUNCTION. lizard reports the code
      # outside every function as one more row, and names it *global*:
      #
      #   self.global_pseudo_function = FunctionInfo("*global*", filename, 0)
      #
      # — its own words, in lizard.py, and the 0 is the start line by
      # construction. It is emitted for C#, Python and the Go-like readers among
      # others, its length is the WHOLE FILE span, and one file can carry several
      # of these rows, byte for byte identical.
      #
      # Three things go wrong if it is taken as a function, and all three did:
      #
      #   - it registers a function_length hotspot claiming a 214-line function
      #     that does not exist. The file is already measured by file_length,
      #     from the file-length tool, so nothing is lost by dropping it.
      #   - several identical rows produce several identical QI keys — same
      #     scope, same start line 0 — and the run stops on the uniqueness
      #     assertion. That is the assertion working: the rows really are
      #     indistinguishable, because they are the same non-function.
      #   - it is the collector own *global* sentinel, character for character.
      #     The scope slot is meant to say "this metric has no function", and a
      #     value arriving from the tool that spells that exactly is not
      #     distinguishable from the collector saying it.
      #
      # Dropped HERE, at the boundary, so no consumer has to know: not the
      # rollups, which would otherwise take a whole-file span as their longest
      # function, and not the clone join, which would otherwise attach the name
      # *global* to any clone in the file, since a 0-to-end span overlaps
      # everything.
      if (f[8] == "*global*") next
      s = (nf >= 10 && f[10] ~ /^[0-9]+$/) ? f[10] : ""
      e = (nf >= 11 && f[11] ~ /^[0-9]+$/) ? f[11] : ""
      if (s != "" && e != "" && (e + 0) < (s + 0)) { s = ""; e = "" }
      print f[7], f[8], f[2], f[5], f[4], s, e
    }
  ' "$raw" > "$raw.rows" || true
  cut -f1 "$raw.rows" | norm_paths > "$raw.p"
  cut -f2- "$raw.rows" > "$raw.r"
  paste "$raw.p" "$raw.r" | LC_ALL=C sort -t$'\t' -k1,1 > "$raw.norm"
  LC_ALL=C sort -u "$files" > "$raw.files"
  LC_ALL=C join -t$'\t' -1 1 -2 1 "$raw.files" "$raw.norm" > "$out" || true
  rm -f "$raw" "$raw.rows" "$raw.p" "$raw.r" "$raw.norm" "$raw.files"
  return 0
}

# dup.tsv: relpath <TAB> lines <TAB> duplicated_lines
# dup.tsv: relpath <TAB> lines <TAB> duplicated_lines
 # dup.tsv: relpath <TAB> lines <TAB> duplicated_lines
run_jscpd() {
  local project_root="$1" scope_arg="$2" files="$3" out="$4" globs="$5" clones_out="${6:-}"
  : > "$out"
  [ -z "$clones_out" ] || : > "$clones_out"

  local rdir raw summary_top
  rdir="$(mktemp -d)"

  summary_top="$(wc -l < "$files" | tr -d ' ')"
  [ -n "$summary_top" ] && [ "$summary_top" -gt 0 ] || summary_top=1

  local -a iargs=()
  # .git is always ignored: with --no-gitignore jscpd walks .git/hooks, and its
  # sample scripts then fill the --summary-top slots meant for measured files.
  iargs=(--ignore "**/.git/**${globs:+,$globs}")

  # ── First try the jscpd v5 form ──────────────────────────────────────────
  #
  # v5 --summary gives us the per-file denominator that is no longer present
  # under statistics.formats.*.sources (in v5, sources is only a count).
  (
    cd "$project_root" &&
    jscpd \
      --silent \
      --no-gitignore \
      --summary \
      --summary-top "$summary_top" \
      --summary-by lines \
      --reporters json \
      --output "$rdir" \
      ${iargs[@]+"${iargs[@]}"} \
      "$scope_arg"
  ) >/dev/null 2>&1 || true

  raw="$rdir/jscpd-report.json"

  # ── Compatibility fallback ───────────────────────────────────────────────
  #
  # Older jscpd versions and the regression-suite fake jscpd may not understand
  # the v5 summary flags. Retry using the long-standing CLI contract.
  if [ ! -f "$raw" ]; then
    (
      cd "$project_root" &&
      jscpd \
        --silent \
        --reporters json \
        --output "$rdir" \
        ${iargs[@]+"${iargs[@]}"} \
        "$scope_arg"
    ) >/dev/null 2>&1 || true
  fi

  [ -f "$raw" ] || {
    rm -rf "$rdir"
    return 1
  }

  # A report file that is not valid JSON is a genuine parse/integration error.
  if ! jq -e '.' "$raw" >/dev/null 2>&1; then
    rm -rf "$rdir"
    return 1
  fi

  : > "$rdir/norm"

  # ── Clone pairs, captured BEFORE the coverage flatten ────────────────────
  #
  # The per-file duplication percentage below is computed by flattening every
  # clone into two independent (file, start, end) intervals — which is correct
  # for coverage and destroys the one thing a reader actually wants, namely
  # WHICH block matches WHICH. So the pairing is teed off here, first, and the
  # coverage path continues untouched (PD-01: the rollup metric does not move).
  #
  # Emitted TSV, one row per clone:
  #   fileA <TAB> startA <TAB> endA <TAB> fileB <TAB> startB <TAB> endB
  #         <TAB> lines <TAB> normalized-fragment
  #
  # The fragment travels as ONE FIELD ON ONE LINE, whitespace-normalised here
  # rather than later: newlines are what would otherwise break the TSV, and
  # normalising is required for the identity hash anyway (see clone_identity).
  # It is used to compute a hash and is then dropped — no verbatim source ever
  # reaches quality.json (PD-03).
  if [ -n "$clones_out" ]; then
    jq -r '
      .duplicates[]?
      | select(.firstFile != null and .secondFile != null)
      | [ (.firstFile.name  // ""),
          (.firstFile.startLoc.line  // .firstFile.start  // 0),
          (.firstFile.endLoc.line    // .firstFile.end    // 0),
          (.secondFile.name // ""),
          (.secondFile.startLoc.line // .secondFile.start // 0),
          (.secondFile.endLoc.line   // .secondFile.end   // 0),
          (.lines // 0),
          # Normalisation, defined here and nowhere else: drop blank lines,
          # strip each line, collapse internal whitespace runs, join with a
          # single space. jscpd detects clones on a TOKEN stream, so two blocks
          # it calls identical can differ in raw indentation — hashing the raw
          # fragment would mint a fresh QI on a pure reindent and resolve the
          # old one. This is SpecClaws normalisation, deliberately close to but
          # NOT claimed to equal jscpds tokenizer.
          ( (.fragment // "")
            | split("\n")
            | map(gsub("^\\s+|\\s+$"; "") | gsub("\\s+"; " "))
            | map(select(length > 0))
            | join(" ") )
        ]
      | @tsv
    ' "$raw" 2>/dev/null \
      | awk -F'\t' -v OFS='\t' -v pfx="$scope_arg" '
          # Per-FIELD path normalisation, mirroring norm_paths in the same order
          # — and it must be per-field, not per-line: norm_paths collapses "//"
          # and strips wrapping quotes, both of which would corrupt the fragment
          # field travelling alongside these paths.
          #
          # THE COLLAPSE STEP IS LOAD-BEARING, for exactly the reason norm_paths
          # documents. jscpd on Windows emits "src\Alpha.cs"; jq @tsv then
          # ESCAPES the backslash to "\\"; folding "\" to "/" therefore yields
          # "src//Alpha.cs", which matches nothing in the measured list. Without
          # the collapse every clone on Windows was silently counted as
          # out-of-scope — a census row that looked like a scoping decision and
          # was really a path bug.
          function normp(p) {
            sub(/\r$/, "", p)
            sub(/^"/, "", p); sub(/"$/, "", p)
            gsub(/\\/, "/", p)
            gsub(/\/\/+/, "/", p)
            sub(/^\.\//, "", p)
            if (pfx != "" && pfx != "." && p != pfx && index(p, pfx "/") != 1) p = pfx "/" p
            return p
          }
          NF >= 7 {
            if ($1 == "" || $4 == "") next
            if ($2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/) next
            if ($5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/) next
            if ($7 !~ /^[0-9]+$/ || $7 + 0 <= 0) next
            print normp($1), $2, $3, normp($4), $5, $6, $7, $8
          }
        ' > "$clones_out" || true
  fi

  # ── Shape A: jscpd v5 summary ────────────────────────────────────────────
  #
  # --summary appends per-file information to the JSON report. Extract every
  # object carrying a file path/name and a line count. Folder summary rows are
  # harmless: the final intersection with measurable.txt removes them.
  if jq -e '.summary != null and (.summary | type == "object")' \
      "$raw" >/dev/null 2>&1; then

    jq -r '
      .summary
      | ..
      | objects
      | select(
          (has("path") or has("name"))
          and (.lines? != null)
        )
      | [
          (.path // .name // ""),
          (.lines // 0)
        ]
      | @tsv
    ' "$raw" 2>/dev/null \
      | norm_paths \
      | awk -F'\t' -v OFS='\t' -v pfx="$scope_arg" '
          {
            path = $1
            lines = $2

            if (path == "" || lines !~ /^[0-9]+$/) next

            # jscpd reports paths relative to the directory it was asked to
            # scan. Restore the repo-relative scope prefix when required.
            if (pfx != "" && pfx != ".") {
              if (path != pfx && index(path, pfx "/") != 1) {
                path = pfx "/" path
              }
            }

            print path, lines
          }
        ' \
      | LC_ALL=C sort -t$'\t' -k1,1 -u \
      > "$rdir/scanned" || true

    if [ -s "$rdir/scanned" ]; then

      # Each duplicate has two source ranges. Both count as duplicated coverage.
      jq -r '
        .duplicates[]?
        | (.firstFile, .secondFile)
        | [
            (.name // ""),
            (.startLoc.line // .start // 0),
            (.endLoc.line // .end // 0)
          ]
        | @tsv
      ' "$raw" 2>/dev/null \
        | norm_paths \
        | awk -F'\t' -v OFS='\t' -v pfx="$scope_arg" '
            {
              path = $1
              start = $2
              end = $3

              if (path == "") next
              if (start !~ /^[0-9]+$/ || end !~ /^[0-9]+$/) next
              if (start < 1 || end < start) next

              if (pfx != "" && pfx != ".") {
                if (path != pfx && index(path, pfx "/") != 1) {
                  path = pfx "/" path
                }
              }

              print path, start, end
            }
          ' > "$rdir/intervals" || true

      # Clone intervals may overlap. Count each duplicated source line only once.
      awk -F'\t' -v OFS='\t' '
        {
          file = $1
          start = $2 + 0
          end = $3 + 0

          for (line = start; line <= end; line++) {
            covered[file SUBSEP line] = 1
          }
        }

        END {
          for (key in covered) {
            split(key, parts, SUBSEP)
            count[parts[1]]++
          }

          for (file in count) {
            print file, count[file]
          }
        }
      ' "$rdir/intervals" \
        | LC_ALL=C sort -t$'\t' -k1,1 \
        > "$rdir/duplicated"

      # Files with no clones still count as successfully measured with zero
      # duplicated lines. FILENAME, not NR == FNR: with zero clones the first
      # file is empty and NR == FNR would stay true across the whole second one.
      awk -F'\t' -v OFS='\t' '
        FILENAME == ARGV[1] {
          duplicated[$1] = $2 + 0
          next
        }

        {
          file = $1
          lines = $2 + 0
          dup = (file in duplicated ? duplicated[file] : 0)

          if (dup > lines) dup = lines

          print file, lines, dup
        }
      ' "$rdir/duplicated" "$rdir/scanned" \
        | LC_ALL=C sort -t$'\t' -k1,1 \
        > "$rdir/norm"
    fi
  fi

  # ── Shape B: legacy / regression-fixture JSON ────────────────────────────
  #
  # Older jscpd reports — and the existing SpecClaw regression fake — may
  # expose per-file data under:
  #
  #   statistics.formats.<format>.sources
  #   statistics.paths
  #
  # In jscpd v5, `sources` is a NUMBER, so type-check it before to_entries.
  # This branch therefore cannot mistake the v5 aggregate count for a map.
  if [ ! -s "$rdir/norm" ]; then
    jq -r '
      def stats:
        (.statistics // .statistic // {});

      def legacy_rows:
        (
          (stats.formats // {})
          | to_entries[]?
          | select(
              (((.value.sources // null) | type) == "object")
            )
          | (.value.sources | to_entries[]?)
        ),
        (
          (stats.paths // {})
          | select(type == "object")
          | to_entries[]?
        );

      [legacy_rows]
      | unique_by(.key)
      | .[]
      | [
          .key,
          (.value.lines // 0),
          (.value.duplicatedLines // 0)
        ]
      | @tsv
    ' "$raw" 2>/dev/null \
      | norm_paths \
      | LC_ALL=C sort -t$'\t' -k1,1 -u \
      > "$rdir/norm" || true
  fi

  # Neither known report shape produced per-file measurement rows.
  [ -s "$rdir/norm" ] || {
    rm -rf "$rdir"
    return 1
  }

  # ── Authoritative SpecClaw scope intersection ────────────────────────────
  #
  # The collector's post-exclusion file list owns scope. jscpd output cannot
  # introduce a file that was excluded upstream.
  LC_ALL=C sort -u "$files" > "$rdir/files"

  LC_ALL=C join -t$'\t' \
    -1 1 -2 1 \
    "$rdir/files" "$rdir/norm" \
    > "$out" || true

  [ -s "$out" ] || {
    rm -rf "$rdir"
    return 1
  }

  rm -rf "$rdir"
  return 0
}

