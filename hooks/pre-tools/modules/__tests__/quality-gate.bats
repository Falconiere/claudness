#!/usr/bin/env bats
# Tests for hooks/pre-tools/modules/quality-gate.sh

HOOK="${BATS_TEST_DIRNAME}/../quality-gate.sh"

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  mkdir -p .claude/tmp
  printf '%s\n' '{"status":"failing","reason":"forced","violations":""}' > .claude/tmp/quality-gate-status.json
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "quality-gate: exits 0 with MY_CLAUDE_QUALITY=off" {
  payload='{"tool_input":{"command":"rm -rf /"}}'
  MY_CLAUDE_QUALITY=off tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "quality-gate: exits 0 in a barebones repo with no toolchain (no detected pm + no cargo blocks nothing extra)" {
  # No state file → exit 0 regardless of toolchain.
  rm -f .claude/tmp/quality-gate-status.json
  payload='{"tool_input":{"command":"echo hi"}}'
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
