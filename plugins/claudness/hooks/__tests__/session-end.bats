#!/usr/bin/env bats
# session-end.sh is the Stop hook. The comemory reminder is OPT-IN (default off):
# it emits only when hooks.session-end is explicitly true.

SCRIPT="${BATS_TEST_DIRNAME}/../session-end.sh"

setup() {
  TMP=$(mktemp -d)
  export HOME="$TMP/home"
  export CLAUDE_PROJECT_DIR="$TMP/proj"
  mkdir -p "$HOME/.claude" "$CLAUDE_PROJECT_DIR/.claude"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

_enable() { echo '{"version":1,"hooks":{"session-end":true}}' > "$HOME/.claude/claudness.config.json"; }

@test "session-end is silent by default (opt-in, no config)" {
  run bash -c "'$SCRIPT' < /dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-end stays silent when explicitly disabled" {
  echo '{"version":1,"hooks":{"session-end":false}}' > "$HOME/.claude/claudness.config.json"
  run bash -c "'$SCRIPT' < /dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-end emits valid JSON with systemMessage when enabled" {
  _enable
  output=$(bash -c "'$SCRIPT' < /dev/null")
  echo "$output" | jq -e '.systemMessage' >/dev/null
}

@test "session-end (enabled) does not emit unrecognized stopReason field" {
  _enable
  output=$(bash -c "'$SCRIPT' < /dev/null")
  ! echo "$output" | jq -e '.stopReason' >/dev/null
}

@test "session-end (enabled) output does not leak source-repo names" {
  _enable
  run bash -c "'$SCRIPT' < /dev/null"
  ! echo "$output" | grep -qE 'yamless|routo|/Volumes/Projects/(routo|yamless)'
}

# Autonomous maintenance is opt-OUT (default on): the once-per-day stamp file
# is written even with no config. Isolated COMEMORY_DATA_DIR so mine/prune/gc
# never touch a real store.
@test "session-end: autonomous comemory maintenance runs by default (stamp written)" {
  command -v comemory >/dev/null 2>&1 || skip "comemory not installed"
  export COMEMORY_DATA_DIR="$TMP/cm"
  run bash -c "'$SCRIPT' < /dev/null"
  [ "$status" -eq 0 ]
  [ -f "$COMEMORY_DATA_DIR/.claudness-last-maintain" ]
}

# Contract fix: hooks.session-end:false disables BOTH the reminder and the
# autonomous maintenance — no stamp, no store mutation.
@test "session-end: hooks.session-end=false disables maintenance (no stamp)" {
  command -v comemory >/dev/null 2>&1 || skip "comemory not installed"
  echo '{"version":1,"hooks":{"session-end":false}}' > "$HOME/.claude/claudness.config.json"
  export COMEMORY_DATA_DIR="$TMP/cm"
  run bash -c "'$SCRIPT' < /dev/null"
  [ "$status" -eq 0 ]
  [ ! -f "$COMEMORY_DATA_DIR/.claudness-last-maintain" ]
}
