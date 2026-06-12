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
  # Reset every loader-state variable so test order cannot leak: cache flag,
  # jq-presence cache, and the cache file path (use a fresh path per test so
  # an on-disk cache from a previous test never satisfies the next).
  CLAUDNESS_CFG_LOADED=0
  _CLAUDNESS_HAS_JQ=""
  CLAUDNESS_CFG_CACHE="$TMP/claudness-cfg.json"
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
  # Use a subshell with env -i so the PATH override stays scoped to the
  # child process; the bats `run` function would otherwise mutate the
  # outer shell's PATH for the remainder of this test.
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c \
    ". \"$REPO_ROOT/hooks/lib/config.sh\"; claudness_engram_state"
  [ "$status" -eq 0 ]
  [ "$output" = "missing" ]
}


@test "claudness_enabled_explicit: disabled by default (no config)" {
  run claudness_enabled_explicit hooks session-end
  [ "$status" -eq 1 ]
}

@test "claudness_enabled_explicit: disabled when key absent but config exists" {
  echo '{"version":1,"skills":{"engram":true}}' > "$HOME/.claude/claudness.config.json"
  run claudness_enabled_explicit hooks session-end
  [ "$status" -eq 1 ]
}

@test "claudness_enabled_explicit: enabled only when explicitly true" {
  echo '{"version":1,"hooks":{"session-end":true}}' > "$HOME/.claude/claudness.config.json"
  run claudness_enabled_explicit hooks session-end
  [ "$status" -eq 0 ]
}

@test "claudness_enabled_explicit: disabled when explicitly false" {
  echo '{"version":1,"hooks":{"session-end":false}}' > "$HOME/.claude/claudness.config.json"
  run claudness_enabled_explicit hooks session-end
  [ "$status" -eq 1 ]
}
