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
