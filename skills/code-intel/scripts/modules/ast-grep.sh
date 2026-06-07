#!/usr/bin/env bash
# ast-grep CLI wrapper — structural/AST code search
# Bakes in --color never to prevent ANSI waste.
# Auto-detects --lang from file extension if the caller did not pass --lang.
set -euo pipefail

# Graceful no-op if neither binary is installed.
if ! command -v sg >/dev/null 2>&1 && ! command -v ast-grep >/dev/null 2>&1; then
  exit 0
fi

# Prefer `sg` (shorter), fall back to `ast-grep`.
if command -v sg >/dev/null 2>&1; then
  AG=sg
else
  AG=ast-grep
fi

subcmd="${1:-}"
shift 2>/dev/null || true

usage() {
  cat <<'USAGE'
Usage: ast-grep.sh <subcommand> [args...]

Subcommands:
  search <pattern> [--lang <L>] [flags]  Pattern search (--color never)
  files <pattern> [--lang <L>] [flags]   File paths only (--files-with-matches)
  scan <yaml> [flags]                    Rule-based scan (--report-style short --max-results 50)
  debug <pattern> [--lang <L>]           Debug pattern AST (--debug-query=pattern)

--lang is required for search/files/debug, but is auto-inferred from the
first path argument's extension if not supplied.

Pass-through flags: --globs <pat>, -A/-B/-C <N>, --max-results N
USAGE
  exit 1
}

# Infer --lang <L> from the first path-like argument if --lang/-l not provided.
infer_lang_args() {
  local has_lang=0 first_path=""
  local arg
  for arg in "$@"; do
    case "$arg" in
      --lang|-l|--lang=*|-l=*) has_lang=1 ;;
    esac
    # First arg that exists on disk
    if [ -z "$first_path" ] && [ -e "$arg" ]; then
      first_path="$arg"
    fi
  done
  if [ "$has_lang" -eq 0 ] && [ -n "$first_path" ] && [ -f "$first_path" ]; then
    case "${first_path##*.}" in
      ts)   echo "--lang typescript" ;;
      tsx)  echo "--lang tsx" ;;
      js|mjs|cjs) echo "--lang javascript" ;;
      jsx)  echo "--lang jsx" ;;
      rs)   echo "--lang rust" ;;
      py)   echo "--lang python" ;;
      go)   echo "--lang go" ;;
      rb)   echo "--lang ruby" ;;
      java) echo "--lang java" ;;
      *)    : ;;
    esac
  fi
}

case "$subcmd" in
  search)
    pattern="${1:?search requires a pattern}"
    shift
    lang_args=$(infer_lang_args "$@")
    # shellcheck disable=SC2086  # $lang_args is intentional word-split
    exec "$AG" run --pattern "$pattern" --color never $lang_args "$@"
    ;;
  files)
    pattern="${1:?files requires a pattern}"
    shift
    lang_args=$(infer_lang_args "$@")
    # shellcheck disable=SC2086  # $lang_args is intentional word-split
    exec "$AG" run --pattern "$pattern" --files-with-matches --color never $lang_args "$@"
    ;;
  scan)
    rules="${1:?scan requires inline YAML or rule file path}"
    shift
    if [[ -f "$rules" ]]; then
      exec "$AG" scan --rule "$rules" --report-style short --max-results 50 --color never "$@"
    else
      exec "$AG" scan --inline-rules "$rules" --report-style short --max-results 50 --color never "$@"
    fi
    ;;
  debug)
    pattern="${1:?debug requires a pattern}"
    shift
    lang_args=$(infer_lang_args "$@")
    # shellcheck disable=SC2086  # $lang_args is intentional word-split
    exec "$AG" run --pattern "$pattern" --debug-query=pattern --color never $lang_args "$@"
    ;;
  *)
    usage
    ;;
esac
