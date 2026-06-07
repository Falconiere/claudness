#!/usr/bin/env bats
# Tests for hooks/pre-tools/modules/mcp-blocker.sh

HOOK="${BATS_TEST_DIRNAME}/../mcp-blocker.sh"

setup() {
  TMP=$(mktemp -d)
  export MY_CLAUDE_SETTINGS_DIR="$TMP/settings"
  mkdir -p "$MY_CLAUDE_SETTINGS_DIR"
  printf '%s\n' "engram" > "$MY_CLAUDE_SETTINGS_DIR/mcp-blocklist.txt"
}

teardown() {
  unset MY_CLAUDE_SETTINGS_DIR
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "mcp-blocker: blocks a listed server" {
  tool_name=mcp__engram__search run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "mcp-blocker: allows an unlisted server" {
  tool_name=mcp__other__do_thing run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
