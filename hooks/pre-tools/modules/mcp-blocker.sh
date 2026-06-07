#!/usr/bin/env bash
# Block MCP tool usage for listed servers — redirect to CLI scripts.
# Data-driven: server name prefixes come from $SETTINGS_DIR/mcp-blocklist.txt.
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked

: "${tool_name:=}"

# shellcheck source=../../lib/detect.sh
. "${BASH_SOURCE%/*}/../../lib/detect.sh"
# shellcheck source=../../lib/config.sh
. "${BASH_SOURCE%/*}/../../lib/config.sh"

command -v jq >/dev/null 2>&1 || exit 0

SETTINGS_DIR=$(detect_settings_dir)
LIST_FILE="$SETTINGS_DIR/mcp-blocklist.txt"

# Only inspect mcp__<server>__* tool names.
case "$tool_name" in
  mcp__*__*) ;;
  *) exit 0 ;;
esac

# Extract the server segment: mcp__<server>__rest
rest="${tool_name#mcp__}"
server="${rest%%__*}"

# read_list is sourced from lib/detect.sh.

disabled_from_cfg=""
claudness_load_config
disabled_from_cfg=$(jq -r '.mcp // {} | to_entries[] | select(.value == false) | .key' \
  "$CLAUDNESS_CFG_CACHE" 2>/dev/null)

file_list="$(read_list "$LIST_FILE")"

# Track WHERE the matching entry came from so the deny reason can point the
# user at the right file to edit.
blocked_source=""
match_entry() {
  local list_input="$1" name
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    # Prefix match: an entry of `claude_ai_` blocks `claude_ai_Canva`. An
    # exact server name is the special case of a prefix with no suffix.
    case "$server" in
      "$name"*) return 0 ;;
    esac
  done <<< "$list_input"
  return 1
}

if match_entry "$file_list"; then
  blocked_source="file"
elif match_entry "$disabled_from_cfg"; then
  blocked_source="config"
fi

if [ -n "$blocked_source" ]; then
  case "$blocked_source" in
    file)
      reason_tail="see settings/mcp-blocklist.txt"
      ;;
    config)
      reason_tail="disabled via claudness config (mcp.$server=false in claudness.config.json)"
      ;;
  esac
  jq -n --arg s "$server" --arg tail "$reason_tail" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("MCP server \"" + $s + "\" is blocked (" + $tail + ").")
    }
  }'
fi
exit 0
