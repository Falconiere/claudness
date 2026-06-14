#!/usr/bin/env bats
# Tests for hooks/lib/registry.sh

setup() {
  . "${BATS_TEST_DIRNAME}/../registry.sh"
  TMP=$(mktemp -d)
  unset CLAUDNESS_CONFIG_DIR CLAUDE_CONFIG_DIR PI_CODING_AGENT_DIR
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

@test "registry_event_dir honors CLAUDNESS_CONFIG_DIR over CLAUDE_CONFIG_DIR" {
  run env CLAUDNESS_CONFIG_DIR="$TMP/cfg" CLAUDE_CONFIG_DIR="$TMP/wrong" bash -c '
    . "'"${BATS_TEST_DIRNAME}"'/../registry.sh"
    claudness_registry_event_dir PreToolUse
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/cfg/claudness/pre-tools.d" ]
}

@test "registry_event_dir honors PI_CODING_AGENT_DIR as fallback" {
  run env -u CLAUDE_CONFIG_DIR -u CLAUDNESS_CONFIG_DIR PI_CODING_AGENT_DIR="$TMP/pi" bash -c '
    . "'"${BATS_TEST_DIRNAME}"'/../registry.sh"
    claudness_registry_event_dir PostToolUse
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/pi/claudness/post-tools.d" ]
}

@test "registry_event_dir falls back to HOME/.claude" {
  run env -u CLAUDE_CONFIG_DIR -u CLAUDNESS_CONFIG_DIR -u PI_CODING_AGENT_DIR HOME="$TMP/home" bash -c '
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
