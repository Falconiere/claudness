#!/usr/bin/env bats
# Tests for the shared dispatcher (hooks/lib/dispatch.sh) under PreToolUse
# semantics, as used by hooks/pre-tools/mod.sh.
#
# Guarantees:
#   - permissionDecision:deny short-circuits subsequent modules.
#   - advisory additionalContext from multiple modules is merged into one
#     final output object (a single advisory does NOT preempt a later deny).
#   - a deny from any module wins even if alphabetically-earlier modules
#     produced advisory output first.
#   - module exit code 2 (Claude Code block convention) propagates: the
#     dispatcher returns 2 and forwards the module's stderr.
#   - any other non-zero module exit is logged and skipped; dispatch continues.

setup() {
  TMP=$(mktemp -d)
  MODULES_DIR="$TMP/modules"
  mkdir -p "$MODULES_DIR"

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  # shellcheck source=../../lib/dispatch.sh
  . "$REPO_ROOT/hooks/lib/dispatch.sh"

  input='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
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

@test "dispatcher: advisory from earlier module does NOT preempt a deny from later module" {
  # Alphabetically first: advisory.
  write_module "a_advisory" 'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"advisory-A\"}}"'
  # Alphabetically later: deny.
  write_module "z_deny"     'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",permissionDecision:\"deny\",permissionDecisionReason:\"blocked-by-Z\"}}"'

  run claudness_dispatch_modules "$MODULES_DIR" "PreToolUse"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("blocked-by-Z")'
}

@test "dispatcher: two advisory modules merge into ONE final output" {
  write_module "a_one" 'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"context-one\"}}"'
  write_module "b_two" 'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"context-two\"}}"'

  run claudness_dispatch_modules "$MODULES_DIR" "PreToolUse"
  [ "$status" -eq 0 ]
  # Exactly one JSON object on stdout.
  count=$(echo "$output" | jq -s 'length')
  [ "$count" = "1" ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("context-one")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("context-two")'
}

@test "dispatcher: deny short-circuits later modules (no trailing advisory after deny)" {
  write_module "a_deny"     'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",permissionDecision:\"deny\",permissionDecisionReason:\"early-deny\"}}"'
  write_module "z_advisory" 'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"should-not-appear\"}}"'

  run claudness_dispatch_modules "$MODULES_DIR" "PreToolUse"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq -s 'length')
  [ "$count" = "1" ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  ! echo "$output" | grep -q "should-not-appear"
}

@test "dispatcher: silent modules produce no output" {
  write_module "a_silent" 'exit 0'
  write_module "b_silent" 'exit 0'

  run claudness_dispatch_modules "$MODULES_DIR" "PreToolUse"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dispatcher: modules receive hook input on stdin" {
  write_module "a_reader" 'tool=$(jq -r ".tool_name" -); jq -n --arg t "$tool" "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:(\"saw-\" + \$t)}}"'

  run claudness_dispatch_modules "$MODULES_DIR" "PreToolUse"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext == "saw-Bash"'
}

@test "dispatcher: module exit 2 propagates as block (status 2, stderr forwarded, later modules skipped)" {
  write_module "a_block"    'echo "hard-block-reason" >&2; exit 2'
  write_module "z_advisory" 'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"should-not-appear\"}}"'

  run claudness_dispatch_modules "$MODULES_DIR" "PreToolUse"
  [ "$status" -eq 2 ]
  # bats merges stderr into $output.
  echo "$output" | grep -q "hard-block-reason"
  ! echo "$output" | grep -q "should-not-appear"
}

@test "dispatcher: module failing with other non-zero exit is skipped, dispatch continues" {
  write_module "a_broken" 'echo "{\"hookSpecificOutput\":{\"additionalContext\":\"partial-garbage\"}}"; exit 1'
  write_module "b_good"   'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"good-context\"}}"'

  run claudness_dispatch_modules "$MODULES_DIR" "PreToolUse"
  [ "$status" -eq 0 ]
  # Failure is visible (warning names the module) but stdout from the failed
  # module is discarded.
  echo "$output" | grep -q "a_broken.sh"
  ! echo "$output" | grep -q "partial-garbage"
  echo "$output" | grep -q "good-context"
}

@test "dispatcher: empty modules dir is a no-op" {
  run claudness_dispatch_modules "$MODULES_DIR" "PreToolUse"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
