#!/usr/bin/env bash
# Block MCP tool usage for listed servers — redirect to CLI scripts.
# Data-driven: server name prefixes come from $SETTINGS_DIR/mcp-blocklist.txt.
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked

: "${tool_name:=}"

_claudness_lib="${CLAUDNESS_LIB_DIR:-${BASH_SOURCE%/*}/../../lib}"
# shellcheck source=../../lib/detect.sh
. "$_claudness_lib/detect.sh"
# shellcheck source=../../lib/config.sh
. "$_claudness_lib/config.sh"

command -v jq >/dev/null 2>&1 || exit 0

# This module is wired as a STANDALONE PreToolUse hook (matcher mcp__), so it
# does NOT go through pre-tools/mod.sh and the parent never `export`s
# tool_name. Claude Code delivers the hook input as JSON on STDIN, including
# .tool_name. When tool_name is not in the env, read it from stdin. Env keeps
# precedence so env-driven tests still pass; stdin is consumed exactly once.
if [[ -z "$tool_name" ]]; then
  _mcp_stdin=$(cat 2>/dev/null || true)
  if [[ -n "$_mcp_stdin" ]]; then
    tool_name=$(jq -r '.tool_name // empty' <<<"$_mcp_stdin" 2>/dev/null || true)
  fi
fi

SETTINGS_DIR=$(detect_settings_dir)
LIST_FILE="$SETTINGS_DIR/mcp-blocklist.txt"

# Only inspect mcp__<server>__* tool names.
case "$tool_name" in
  mcp__*__*) ;;
  *) exit 0 ;;
esac

# Fast-path: matcher widened from mcp__engram to mcp__ now routes every MCP
# tool call through here. Skip config-load work entirely when there is no
# blocklist file AND no user/project config to consult — the common case for
# anyone who has not opted into the gate.
if [ ! -f "$LIST_FILE" ] && ! claudness_config_exists; then
  exit 0
fi

# Extract the server segment: mcp__<server>__rest
rest="${tool_name#mcp__}"
server="${rest%%__*}"

# read_list is sourced from lib/detect.sh.

claudness_load_config
# `objects` guards against a malformed `.mcp` (string/array) — to_entries
# would error on a non-object; with the guard it is simply a no-op.
disabled_from_cfg=$(jq -r '.mcp // {} | objects | to_entries[] | select(.value == false) | .key' \
  <<< "${CLAUDNESS_CFG_JSON:-}" 2>/dev/null)

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
  jq -n \
    --arg s "$server" \
    --arg src "$blocked_source" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: (
          "MCP server \"" + $s + "\" is blocked (" +
          (if $src == "file"
            then "see settings/mcp-blocklist.txt"
            else "disabled via claudness config (mcp." + $s + "=false in claudness.config.json)"
           end) +
          ")."
        )
      }
    }'
fi
exit 0
