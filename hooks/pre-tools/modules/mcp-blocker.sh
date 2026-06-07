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
if command -v jq >/dev/null 2>&1; then
  disabled_from_cfg=$(jq -r '.mcp // {} | to_entries[] | select(.value == false) | .key' \
    "$CLAUDNESS_CFG_CACHE" 2>/dev/null)
fi

combined="$(read_list "$LIST_FILE")
$disabled_from_cfg"

blocked=0
while IFS= read -r name; do
  [ -z "$name" ] && continue
  # Prefix match: an entry of `claude_ai_` blocks `claude_ai_Canva`. An exact
  # server name is the special case of a prefix with no extra characters.
  case "$server" in
    "$name"*) blocked=1; break ;;
  esac
done <<< "$combined"

if [ "$blocked" = 1 ]; then
  jq -n --arg s "$server" '{
    "decision": "block",
    "reason": ("MCP server \"" + $s + "\" is blocked. Use the corresponding CLI wrapper instead (see settings/mcp-blocklist.txt).")
  }'
fi
exit 0
