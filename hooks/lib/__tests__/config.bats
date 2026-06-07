#!/usr/bin/env bats
# Tests for hooks/lib/config.sh.

setup() {
  TMP=$(mktemp -d)
  export HOME="$TMP/home"
  export CLAUDE_PROJECT_DIR="$TMP/project"
  mkdir -p "$HOME/.claude" "$CLAUDE_PROJECT_DIR/.claude"

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  # shellcheck source=../config.sh
  . "$REPO_ROOT/hooks/lib/config.sh"
  CLAUDNESS_CFG_LOADED=0
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

@test "enabled by default when no config files exist" {
  run claudness_enabled skills engram
  [ "$status" -eq 0 ]
}

@test "user config disables skill" {
  echo '{"version":1,"skills":{"engram":false}}' > "$HOME/.claude/claudness.config.json"
  run claudness_enabled skills engram
  [ "$status" -eq 1 ]
}

@test "project config overrides user config" {
  echo '{"version":1,"skills":{"engram":false}}' > "$HOME/.claude/claudness.config.json"
  echo '{"version":1,"skills":{"engram":true}}'  > "$CLAUDE_PROJECT_DIR/.claude/claudness.config.json"
  run claudness_enabled skills engram
  [ "$status" -eq 0 ]
}

@test "unrelated category remains enabled" {
  echo '{"version":1,"skills":{"engram":false}}' > "$HOME/.claude/claudness.config.json"
  run claudness_enabled hooks session-start
  [ "$status" -eq 0 ]
}

@test "malformed user JSON falls back to defaults" {
  printf '{' > "$HOME/.claude/claudness.config.json"
  run claudness_enabled skills engram
  [ "$status" -eq 0 ]
}

@test "engram_state returns 'disabled' when skills.engram=false" {
  echo '{"version":1,"skills":{"engram":false}}' > "$HOME/.claude/claudness.config.json"
  run claudness_engram_state
  [ "$status" -eq 0 ]
  [ "$output" = "disabled" ]
}

@test "engram_state returns 'missing' when enabled but CLI absent" {
  PATH=/usr/bin:/bin run claudness_engram_state
  [ "$status" -eq 0 ]
  [ "$output" = "missing" ]
}

