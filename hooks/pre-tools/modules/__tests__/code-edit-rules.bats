#!/usr/bin/env bats
# Tests for hooks/pre-tools/modules/code-edit-rules.sh

HOOK="${BATS_TEST_DIRNAME}/../code-edit-rules.sh"

setup() {
  TMP=$(mktemp -d)
  export MY_CLAUDE_SETTINGS_DIR="$TMP/settings"
  mkdir -p "$MY_CLAUDE_SETTINGS_DIR"
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

@test "code-edit-rules: empty rules → no-op" {
  printf '%s\n' '{"rules":[]}' > "$MY_CLAUDE_SETTINGS_DIR/code-edit-rules.json"
  run_hook "/abs/src/foo.rs"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code-edit-rules: missing file → no-op" {
  # No code-edit-rules.json in MY_CLAUDE_SETTINGS_DIR.
  run_hook "/abs/src/foo.rs"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code-edit-rules: matching glob surfaces docs" {
  cat > "$MY_CLAUDE_SETTINGS_DIR/code-edit-rules.json" <<'JSON'
{ "rules": [ { "match": "*.rs", "docs": ["rust.md"] } ] }
JSON
  run_hook "/abs/src/foo.rs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("rust.md")'
}
