#!/usr/bin/env bats
# Tests for hooks/lib/registry.sh

setup() {
  . "${BATS_TEST_DIRNAME}/../registry.sh"
  TMP=$(mktemp -d)
}
teardown() { rm -rf "$TMP"; }

@test "registry_event_dir honors CLAUDE_CONFIG_DIR" {
  run env CLAUDE_CONFIG_DIR="$TMP/cfg" bash -c '
    . "'"${BATS_TEST_DIRNAME}"'/../registry.sh"
    claudness_registry_event_dir PreToolUse
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/cfg/claudness/pre-tools.d" ]
}

@test "registry_event_dir falls back to HOME/.claude" {
  run env -u CLAUDE_CONFIG_DIR HOME="$TMP/home" bash -c '
    . "'"${BATS_TEST_DIRNAME}"'/../registry.sh"
    claudness_registry_event_dir PostToolUse
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/home/.claude/claudness/post-tools.d" ]
}

@test "registry_event_dir maps unknown event to a sanitized name" {
  run bash -c '
    . "'"${BATS_TEST_DIRNAME}"'/../registry.sh"
    CLAUDE_CONFIG_DIR="'"$TMP"'" claudness_registry_event_dir SessionStart
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/claudness/session-start.d" ]
}
