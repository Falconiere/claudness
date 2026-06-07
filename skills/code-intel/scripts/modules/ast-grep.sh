#!/bin/bash
# ast-grep CLI wrapper — structural/AST code search
# Bakes in --color never to prevent ANSI waste
set -euo pipefail

subcmd="${1:-}"
shift 2>/dev/null || true

usage() {
  cat <<'USAGE'
Usage: ast-grep.sh <subcommand> [args...]

Subcommands:
  search <pattern> --lang <L> [flags]  Pattern search (--color never)
  files <pattern> --lang <L> [flags]   File paths only (--files-with-matches)
  scan <yaml> [flags]                  Rule-based scan (--report-style short --max-results 50)
  debug <pattern> --lang <L>           Debug pattern AST (--debug-query=pattern)

--lang is required for search/files/debug.
Pass-through flags: --globs <pat>, -A/-B/-C <N>, --max-results N
USAGE
  exit 1
}

case "$subcmd" in
  search)
    pattern="${1:?search requires a pattern}"
    shift
    exec ast-grep run --pattern "$pattern" --color never "$@"
    ;;
  files)
    pattern="${1:?files requires a pattern}"
    shift
    exec ast-grep run --pattern "$pattern" --files-with-matches --color never "$@"
    ;;
  scan)
    rules="${1:?scan requires inline YAML or rule file path}"
    shift
    if [[ -f "$rules" ]]; then
      exec ast-grep scan --rule "$rules" --report-style short --max-results 50 --color never "$@"
    else
      exec ast-grep scan --inline-rules "$rules" --report-style short --max-results 50 --color never "$@"
    fi
    ;;
  debug)
    pattern="${1:?debug requires a pattern}"
    shift
    exec ast-grep run --pattern "$pattern" --debug-query=pattern --color never "$@"
    ;;
  *)
    usage
    ;;
esac
