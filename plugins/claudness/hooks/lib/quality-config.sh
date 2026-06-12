#!/usr/bin/env bash
# Quality-threshold resolver for the lang-quality hooks.
#
# Limits are NOT hardcoded in the quality modules. Each threshold resolves with
# this precedence (first hit wins, always a positive integer):
#   1. Project / user override — `lang.<lang>.<key>` in the merged claudness
#      config (.claude/claudness.config.json), via lib/config.sh.
#   2. Native tool config (TS + maxFileLines only) — the `max-lines` rule from
#      .eslintrc.json / .oxlintrc.json. Flat eslint config (eslint.config.{js,mjs,ts})
#      is JS and NOT parseable here — skipped gracefully.
#   3. Built-in default (DEFAULT_* below).
#
# Every reader is guarded (jq present, file present) and 2>/dev/null — any
# failure falls through to the next layer. Never errors, never blocks a tool.
#
# Source via:  . "$CLAUDNESS_LIB_DIR/quality-config.sh"
# (pulls in config.sh + detect.sh from the same dir).

_QC_LIB_DIR="${CLAUDNESS_LIB_DIR:-${BASH_SOURCE%/*}}"
# shellcheck source=./config.sh
[ -f "$_QC_LIB_DIR/config.sh" ] && . "$_QC_LIB_DIR/config.sh"
# shellcheck source=./detect.sh
[ -f "$_QC_LIB_DIR/detect.sh" ] && . "$_QC_LIB_DIR/detect.sh"

# Built-in defaults — single source of truth, overridable from the environment
# (tests set these to assert fall-through without touching call sites).
: "${DEFAULT_TS_MAX_FILE_LINES:=300}"
: "${DEFAULT_TS_MAX_FN_LINES:=60}"
: "${DEFAULT_RUST_MAX_FILE_LINES:=500}"
: "${DEFAULT_RUST_MAX_FN_LINES:=50}"
: "${DEFAULT_RUST_MAX_IMPL_LINES:=200}"

# One jq filter that normalizes every eslint/oxlint `max-lines` encoding to a
# positive integer (or empty): bare number, ["error", N], ["error", {"max": N}].
# "off" / 0 / negatives / missing all yield empty -> the layer is skipped.
_QC_ESLINT_MAXLINES_FILTER='
  .rules?["max-lines"]?
  | if   type=="number" then .
    elif type=="array"  then ( .[1]
          | if   type=="number" then .
            elif type=="object" then .max
            else empty end )
    else empty end
  | if type=="number" and . > 0 then (.|floor|tostring) else empty end
'

# _qc_project_override LANG KEY  ->  echoes a positive int or "".
# Reads the already-merged config cache (config.sh handles user+project merge,
# malformed JSON, and missing jq).
_qc_project_override() {
  local lang="$1" key="$2"
  command -v claudness_load_config >/dev/null 2>&1 || return 0
  claudness_load_config
  [ "${_CLAUDNESS_HAS_JQ:-0}" = "1" ] || return 0
  [ -f "$CLAUDNESS_CFG_CACHE" ] || return 0
  jq -r --arg l "$lang" --arg k "$key" '
    ((.lang? // {})[$l]? // {})[$k]?
    | if type=="number" and . > 0 then (.|floor|tostring) else empty end
  ' "$CLAUDNESS_CFG_CACHE" 2>/dev/null
}

# _qc_native_ts_max_lines  ->  echoes a positive int or "".
# eslint legacy JSON first, then oxlint. Read at the git root only.
_qc_native_ts_max_lines() {
  command -v jq >/dev/null 2>&1 || return 0
  local root f v
  root=$(detect_project_root)
  [ -n "$root" ] || return 0
  for f in "$root/.eslintrc.json" "$root/.oxlintrc.json"; do
    [ -f "$f" ] || continue
    v=$(jq -r "$_QC_ESLINT_MAXLINES_FILTER" "$f" 2>/dev/null)
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
}

# quality_threshold LANG KEY DEFAULT  ->  always echoes a positive integer.
quality_threshold() {
  local lang="$1" key="$2" def="$3" v
  v=$(_qc_project_override "$lang" "$key")
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  if [ "$lang" = "ts" ] && [ "$key" = "maxFileLines" ]; then
    v=$(_qc_native_ts_max_lines)
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  fi
  printf '%s' "$def"
}

# count_code_lines FILE  ->  lines of real code (blank lines and comments
# excluded). Handles // line comments and /* ... */ blocks (incl. multi-line and
# inline), for both TS and Rust (/// and //! reduce to // and are dropped).
# Heuristic: does not track // or /* inside string literals — consistent with
# the other comment-stripping passes in the quality modules.
count_code_lines() {
  awk '
    BEGIN { inblock=0; n=0 }
    {
      line=$0
      if (inblock) {
        idx=index(line,"*/")
        if (idx>0) { line=substr(line, idx+2); inblock=0 } else next
      }
      while ((s=index(line,"/*"))>0) {
        rest=substr(line, s+2); e=index(rest,"*/")
        if (e>0) { line=substr(line,1,s-1) substr(rest, e+2) }
        else { line=substr(line,1,s-1); inblock=1; break }
      }
      c=index(line,"//"); if (c>0) line=substr(line,1,c-1)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (length(line)>0) n++
    }
    END { print n }
  ' "$1" 2>/dev/null
}

# Convenience wrappers the quality modules call.
ts_max_file_lines()   { quality_threshold ts   maxFileLines "$DEFAULT_TS_MAX_FILE_LINES"; }
ts_max_fn_lines()     { quality_threshold ts   maxFnLines   "$DEFAULT_TS_MAX_FN_LINES"; }
rust_max_file_lines() { quality_threshold rust maxFileLines "$DEFAULT_RUST_MAX_FILE_LINES"; }
rust_max_fn_lines()   { quality_threshold rust maxFnLines   "$DEFAULT_RUST_MAX_FN_LINES"; }
rust_max_impl_lines() { quality_threshold rust maxImplLines "$DEFAULT_RUST_MAX_IMPL_LINES"; }
