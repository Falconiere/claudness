#!/usr/bin/env bats
# Tests for hooks/post-tools/modules/gate-status.sh

HOOK="${BATS_TEST_DIRNAME}/../gate-status.sh"

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  GATE_FILE="$TMP/.claude/tmp/quality-gate-status.json"
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# Build a PostToolUse Bash payload for a command + exit code.
# Usage: _payload "cargo clippy" 0
_payload() {
  jq -n --arg cmd "$1" --argjson code "$2" \
    '{tool_input: {command: $cmd}, tool_response: {metadata: {exit_code: $code}}}'
}

# Seed the gate file with a given source + status.
# Usage: _write_gate "rust-quality-hook" "failing"
_write_gate() {
  mkdir -p "$TMP/.claude/tmp"
  jq -n --arg source "$1" --arg status "$2" \
    '{status: $status, source: $source, reason: "seeded by test", updatedAt: "2026-01-01T00:00:00Z"}' \
    > "$GATE_FILE"
}

@test "gate-status: non-Bash tool is a no-op (no gate file created)" {
  payload=$(_payload "cargo test" 0)
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ ! -f "$GATE_FILE" ]
}

@test "gate-status: non-quality command does not create a gate file" {
  payload=$(_payload "ls -la" 0)
  tool_name=Bash input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ ! -f "$GATE_FILE" ]
}

@test "gate-status: successful quality command writes passing gate when none exists" {
  payload=$(_payload "cargo clippy" 0)
  tool_name=Bash input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -f "$GATE_FILE" ]
  jq -e '.status == "passing"' "$GATE_FILE"
}

@test "gate-status: failed quality command writes failing gate and emits context" {
  payload=$(_payload "bun test" 1)
  tool_name=Bash input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "failing"' "$GATE_FILE"
  jq -e '.source == "gate-status-hook"' "$GATE_FILE"
  echo "$output" | grep -q "Global quality gate failing"
}

@test "gate-status: failing rust-quality-hook gate survives unrelated successful quality command" {
  _write_gate "rust-quality-hook" "failing"
  payload=$(_payload "cargo clippy" 0)
  tool_name=Bash input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "failing"' "$GATE_FILE"
  jq -e '.source == "rust-quality-hook"' "$GATE_FILE"
}

@test "gate-status: failing ts-quality-hook gate survives unrelated successful quality command" {
  _write_gate "ts-quality-hook" "failing"
  payload=$(_payload "bun run check" 0)
  tool_name=Bash input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "failing"' "$GATE_FILE"
  jq -e '.source == "ts-quality-hook"' "$GATE_FILE"
}

@test "gate-status: failing gate-status-hook gate flips to passing when quality command passes" {
  _write_gate "gate-status-hook" "failing"
  payload=$(_payload "cargo test" 0)
  tool_name=Bash input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "passing"' "$GATE_FILE"
}

@test "gate-status: passing quality-hook gate can be overwritten by failing quality command" {
  _write_gate "ts-quality-hook" "passing"
  payload=$(_payload "bun test" 1)
  tool_name=Bash input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "failing"' "$GATE_FILE"
  jq -e '.source == "gate-status-hook"' "$GATE_FILE"
}
