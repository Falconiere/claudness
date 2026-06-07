#!/usr/bin/env bats
# Tests for hooks/pre-tools/modules/protected-files.sh

HOOK="${BATS_TEST_DIRNAME}/../protected-files.sh"

setup() {
  TMP=$(mktemp -d)
  export MY_CLAUDE_SETTINGS_DIR="$TMP/settings"
  mkdir -p "$MY_CLAUDE_SETTINGS_DIR"
  cat > "$MY_CLAUDE_SETTINGS_DIR/protected-files.txt" <<'TXT'
.env
.env.*
**/secrets/**
hooks/lib/**
hooks/**/*.sh
TXT
}

teardown() {
  unset MY_CLAUDE_SETTINGS_DIR
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

run_hook() {
  local file="$1"
  local payload
  payload=$(jq -n --arg p "$file" '{tool_name:"Edit",tool_input:{file_path:$p}}')
  tool_name=Edit input="$payload" run bash "$HOOK" <<<"$payload"
}

@test "protected-files: blocks .env (bare basename)" {
  run_hook ".env"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "protected-files: blocks hooks/lib/detect.sh (path glob)" {
  run_hook "hooks/lib/detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "protected-files: allows src/foo.ts" {
  run_hook "src/foo.ts"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
