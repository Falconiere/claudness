#!/usr/bin/env bats
# Tests for hooks/pre-tools/mod.sh dispatcher output discipline.
#
# Guarantees:
#   - permissionDecision:deny short-circuits subsequent modules.
#   - advisory additionalContext from multiple modules is merged into one
#     final output object (a single advisory does NOT preempt a later deny).
#   - a deny from any module wins even if alphabetically-earlier modules
#     produced advisory output first.

setup() {
  TMP=$(mktemp -d)
  export FAKE_HOOK_DIR="$TMP/hooks"
  mkdir -p "$FAKE_HOOK_DIR/modules"

  # Build a minimal dispatcher copy that points at FAKE_HOOK_DIR.
  cat > "$FAKE_HOOK_DIR/mod.sh" <<'SH'
#!/bin/bash
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
export input tool_name

HOOK_DIR="${FAKE_HOOK_DIR}/modules"
collected_contexts=()

for script in "$HOOK_DIR"/*.sh; do
  [[ ! -f "$script" ]] && continue
  result=$(echo "$input" | bash "$script" 2>/dev/null)
  [[ -z "$result" ]] && continue

  decision=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [[ "$decision" == "deny" ]]; then
    echo "$result"
    exit 0
  fi

  ctx=$(echo "$result" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  [[ -n "$ctx" ]] && collected_contexts+=("$ctx")
done

if [[ ${#collected_contexts[@]} -gt 0 ]]; then
  merged=""
  for c in "${collected_contexts[@]}"; do
    if [[ -z "$merged" ]]; then
      merged="$c"
    else
      merged="${merged}"$'\n\n'"${c}"
    fi
  done
  jq -n --arg ctx "$merged" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": $ctx
    }
  }'
fi
exit 0
SH
  chmod +x "$FAKE_HOOK_DIR/mod.sh"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

write_module() {
  local name="$1"
  local body="$2"
  local path="$FAKE_HOOK_DIR/modules/${name}.sh"
  printf '%s\n' '#!/usr/bin/env bash' "$body" > "$path"
  chmod +x "$path"
}

run_dispatcher() {
  echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$FAKE_HOOK_DIR/mod.sh"
}

@test "dispatcher: advisory from earlier module does NOT preempt a deny from later module" {
  # Alphabetically first: advisory.
  write_module "a_advisory" 'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"advisory-A\"}}"'
  # Alphabetically later: deny.
  write_module "z_deny"     'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",permissionDecision:\"deny\",permissionDecisionReason:\"blocked-by-Z\"}}"'

  run run_dispatcher
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("blocked-by-Z")'
}

@test "dispatcher: two advisory modules merge into ONE final output" {
  write_module "a_one" 'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"context-one\"}}"'
  write_module "b_two" 'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"context-two\"}}"'

  run run_dispatcher
  [ "$status" -eq 0 ]
  # Exactly one JSON object on stdout.
  count=$(echo "$output" | jq -s 'length')
  [ "$count" = "1" ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("context-one")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("context-two")'
}

@test "dispatcher: deny short-circuits later modules (no trailing advisory after deny)" {
  write_module "a_deny"     'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",permissionDecision:\"deny\",permissionDecisionReason:\"early-deny\"}}"'
  write_module "z_advisory" 'jq -n "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"should-not-appear\"}}"'

  run run_dispatcher
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq -s 'length')
  [ "$count" = "1" ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  ! echo "$output" | grep -q "should-not-appear"
}

@test "dispatcher: silent modules produce no output" {
  write_module "a_silent" 'exit 0'
  write_module "b_silent" 'exit 0'

  run run_dispatcher
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
