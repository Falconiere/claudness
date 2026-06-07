#!/usr/bin/env bats
# Tests for hooks/pre-tools/modules/bash-commands.sh

HOOK="${BATS_TEST_DIRNAME}/../bash-commands.sh"

setup() {
  TMP=$(mktemp -d)
  export MY_CLAUDE_SETTINGS_DIR="$TMP/settings"
  mkdir -p "$MY_CLAUDE_SETTINGS_DIR"
}

teardown() {
  unset MY_CLAUDE_SETTINGS_DIR
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

write_lists() {
  printf '%s\n' "$1" > "$MY_CLAUDE_SETTINGS_DIR/bash-allowlist.txt"
  printf '%s\n' "$2" > "$MY_CLAUDE_SETTINGS_DIR/bash-denylist.txt"
}

run_hook() {
  local cmd="$1"
  local payload
  payload=$(jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  tool_name=Bash input="$payload" run bash "$HOOK" <<<"$payload"
}

@test "bash-commands: accepts an allowed command (no deny match)" {
  write_lists "" ""
  run_hook "ls -la"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bash-commands: rejects a denied command (substring match)" {
  write_lists "" "biome"
  run_hook "biome check ."
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "bash-commands: rejects 'node -e' argv-aware even if 'node' alone might be allowed" {
  # node -e is a multi-token argv-aware rule.
  write_lists "" "node -e"
  run_hook 'node -e "console.log(1)"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "bash-commands: rejects 'git push --force origin feat/x'" {
  write_lists "" "git push --force"
  run_hook "git push --force origin feat/x"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "bash-commands: no-op when data files are missing" {
  # Use a settings dir with no lists at all.
  rm -f "$MY_CLAUDE_SETTINGS_DIR/bash-allowlist.txt" "$MY_CLAUDE_SETTINGS_DIR/bash-denylist.txt"
  run_hook "node -e 'rm -rf /'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bash-commands: bare 'node script.js' does NOT trip 'node -e' argv rule" {
  write_lists "" "node -e"
  run_hook "node script.js"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
