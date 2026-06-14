#!/usr/bin/env bats
# Tests for the shared dispatcher (hooks/lib/dispatch.sh) under PostToolUse
# semantics, as used by hooks/post-tools/mod.sh.
#
# Guarantees:
#   - a module emitting top-level decision:"block" is authoritative: its
#     output is emitted immediately and later modules are skipped.
#   - permissionDecision is a PreToolUse-only concept and is IGNORED here
#     (PostToolUse hooks use decision:"block" + reason).
#   - advisory additionalContext from multiple modules merges into ONE object.
#   - top-level systemMessage advisories are merged into the final object.
#   - a module exiting non-zero (other than 2) does not kill the dispatcher.
#   - empty modules dir is a no-op.

setup() {
  TMP=$(mktemp -d)
  MODULES_DIR="$TMP/modules"
  mkdir -p "$MODULES_DIR"

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  # shellcheck source=../../lib/dispatch.sh
  . "$REPO_ROOT/hooks/lib/dispatch.sh"

  input='{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"stdout":""}}'
  export input
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

write_module() {
  local name="$1"
  local body="$2"
  local path="$MODULES_DIR/${name}.sh"
  printf '%s\n' '#!/usr/bin/env bash' "$body" > "$path"
  chmod +x "$path"
}

@test "post dispatcher: decision:block short-circuits later modules" {
  write_module "a_block"    'jq -n "{decision:\"block\",reason:\"blocked-by-A\"}"'
  write_module "z_advisory" 'jq -n "{hookSpecificOutput:{hookEventName:\"PostToolUse\",additionalContext:\"should-not-appear\"}}"'

  run toolu_dispatch_modules "$MODULES_DIR" "PostToolUse"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq -s 'length')
  [ "$count" = "1" ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("blocked-by-A")'
  ! echo "$output" | grep -q "should-not-appear"
}

@test "post dispatcher: advisory does NOT preempt a later block" {
  write_module "a_advisory" 'jq -n "{hookSpecificOutput:{hookEventName:\"PostToolUse\",additionalContext:\"advisory-A\"}}"'
  write_module "z_block"    'jq -n "{decision:\"block\",reason:\"blocked-by-Z\"}"'

  run toolu_dispatch_modules "$MODULES_DIR" "PostToolUse"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("blocked-by-Z")'
}

@test "post dispatcher: permissionDecision deny is ignored (PreToolUse-only field)" {
  write_module "a_deny"     'jq -n "{hookSpecificOutput:{hookEventName:\"PostToolUse\",permissionDecision:\"deny\",permissionDecisionReason:\"stale-pre-semantics\"}}"'
  write_module "b_advisory" 'jq -n "{hookSpecificOutput:{hookEventName:\"PostToolUse\",additionalContext:\"still-runs\"}}"'

  run toolu_dispatch_modules "$MODULES_DIR" "PostToolUse"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "stale-pre-semantics"
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("still-runs")'
}

@test "post dispatcher: two advisory modules merge into ONE final output" {
  write_module "a_one" 'jq -n "{hookSpecificOutput:{hookEventName:\"PostToolUse\",additionalContext:\"context-one\"}}"'
  write_module "b_two" 'jq -n "{hookSpecificOutput:{hookEventName:\"PostToolUse\",additionalContext:\"context-two\"}}"'

  run toolu_dispatch_modules "$MODULES_DIR" "PostToolUse"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq -s 'length')
  [ "$count" = "1" ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("context-one")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("context-two")'
}

@test "post dispatcher: systemMessage advisories are merged into the final output" {
  write_module "a_msg" 'jq -n "{systemMessage:\"message-one\"}"'
  write_module "b_ctx" 'jq -n "{hookSpecificOutput:{hookEventName:\"PostToolUse\",additionalContext:\"context-two\"},systemMessage:\"message-two\"}"'

  run toolu_dispatch_modules "$MODULES_DIR" "PostToolUse"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq -s 'length')
  [ "$count" = "1" ]
  echo "$output" | jq -e '.systemMessage | test("message-one")'
  echo "$output" | jq -e '.systemMessage | test("message-two")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext == "context-two"'
}

@test "post dispatcher: module exiting non-zero does not kill the dispatcher" {
  write_module "a_broken" 'echo "boom" >&2; exit 1'
  write_module "b_good"   'jq -n "{hookSpecificOutput:{hookEventName:\"PostToolUse\",additionalContext:\"good-context\"}}"'

  run toolu_dispatch_modules "$MODULES_DIR" "PostToolUse"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "a_broken.sh"
  echo "$output" | grep -q "good-context"
}

@test "post dispatcher: module exit 2 propagates as block (status 2, stderr forwarded)" {
  write_module "a_block" 'echo "post-hard-block" >&2; exit 2'

  run toolu_dispatch_modules "$MODULES_DIR" "PostToolUse"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "post-hard-block"
}

@test "post dispatcher: empty modules dir is a no-op" {
  run toolu_dispatch_modules "$MODULES_DIR" "PostToolUse"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
