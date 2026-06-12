#!/bin/bash
# Code-intel script dispatcher
# Usage: mod.sh <tool> <subcommand> [args...]
# Dispatches to modules/<tool>.sh <subcommand> [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

tool="${1:-}"
shift 2>/dev/null || true

if [[ -z "$tool" ]]; then
  cat <<'USAGE'
Usage: mod.sh <tool> <subcommand> [args...]

Tools:
  comemory    Persistent memory + code-intel (search, save, list, search-code,
              graph, feedback, mine, prune, gc, maintain — run comemory.sh for all)
  ast-grep    Structural/AST pattern matching

Examples:
  mod.sh comemory save "Fixed bug" "Root cause was X"
  mod.sh ast-grep search 'fn $NAME($$$ARGS)' --lang rust
USAGE
  exit 1
fi

module="$MODULES_DIR/$tool.sh"

if [[ ! -f "$module" ]]; then
  echo "Error: Unknown tool '$tool'. Available: comemory, ast-grep" >&2
  exit 1
fi

exec bash "$module" "$@"
