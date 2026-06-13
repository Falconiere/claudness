#!/usr/bin/env bats
# Tests for the statusliner SessionStart hook. Real filesystem, no mocks:
# the hook is run with a real temp CLAUDE_CONFIG_DIR and the resulting symlink
# is inspected on disk.

HOOK="${BATS_TEST_DIRNAME}/../session-start.sh"

setup() {
  TMP=$(mktemp -d)
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "session-start: symlinks the statusline to the statusliner registry root" {
  CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$HOOK" </dev/null
  dst="$TMP/cfg/statusliner/statusline.sh"
  [ -L "$dst" ]
  target=$(readlink "$dst")
  [[ "$target" == *"/statusline.sh" ]]
  [ -f "$target" ]
}

@test "session-start: refreshes its own stale symlink" {
  mkdir -p "$TMP/cfg/statusliner"
  ln -s "$TMP/cfg/statusliner/gone.sh" "$TMP/cfg/statusliner/statusline.sh"
  CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$HOOK" </dev/null
  dst="$TMP/cfg/statusliner/statusline.sh"
  [ -L "$dst" ]
  [ -f "$(readlink "$dst")" ]
}

@test "session-start: never clobbers a real file at the symlink path" {
  mkdir -p "$TMP/cfg/statusliner"
  printf 'user owns this' > "$TMP/cfg/statusliner/statusline.sh"
  CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$HOOK" </dev/null
  dst="$TMP/cfg/statusliner/statusline.sh"
  [ ! -L "$dst" ]
  [ "$(cat "$dst")" = "user owns this" ]
}
