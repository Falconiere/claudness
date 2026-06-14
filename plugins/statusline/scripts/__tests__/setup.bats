#!/usr/bin/env bats
# Tests for /statusline:setup. Real filesystem, no mocks: the script runs
# against a real temp CLAUDE_CONFIG_DIR and the resulting settings.json is
# parsed back off disk.

SETUP="${BATS_TEST_DIRNAME}/../setup.sh"

setup() {
  TMP=$(mktemp -d)
  CFG="$TMP/cfg"
  mkdir -p "$CFG"
  SETTINGS="$CFG/settings.json"
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# Read settings.json's statusLine.command back off disk.
cmd_field() {
  python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('statusLine',{}).get('command',''))" "$SETTINGS"
}

@test "setup: creates settings.json when absent" {
  run env CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP"
  [ "$status" -eq 0 ]
  [[ "$output" == CREATED* ]]
  [ -f "$SETTINGS" ]
  [[ "$(cmd_field)" == *"statusline/statusline.sh"* ]]
}

@test "setup: adds statusLine to an existing settings.json, preserving other keys" {
  printf '{\n  "theme": "dark"\n}\n' > "$SETTINGS"
  run env CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP"
  [ "$status" -eq 0 ]
  [[ "$output" == WIRED* ]]
  # Existing key survives.
  [ "$(python3 -c "import json;print(json.load(open('$SETTINGS'))['theme'])")" = "dark" ]
  [[ "$(cmd_field)" == *"statusline/statusline.sh"* ]]
  # A backup was written before the edit.
  [ -f "$SETTINGS.bak" ]
}

@test "setup: is idempotent — second run is a no-op" {
  env CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP" >/dev/null
  run env CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP"
  [ "$status" -eq 0 ]
  [[ "$output" == ALREADY* ]]
}

@test "setup: refuses to clobber a custom statusLine without --force" {
  printf '{\n  "statusLine": { "type": "command", "command": "my-custom-bar" }\n}\n' > "$SETTINGS"
  run env CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP"
  [ "$status" -eq 3 ]
  [[ "$output" == REFUSED* ]]
  # Custom value is left untouched.
  [ "$(cmd_field)" = "my-custom-bar" ]
  [ ! -f "$SETTINGS.bak" ]
}

@test "setup: --force replaces a custom statusLine (after backing it up)" {
  printf '{\n  "statusLine": { "type": "command", "command": "my-custom-bar" }\n}\n' > "$SETTINGS"
  run env CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP" --force
  [ "$status" -eq 0 ]
  [[ "$output" == WIRED* ]]
  [[ "$(cmd_field)" == *"statusline/statusline.sh"* ]]
  [ -f "$SETTINGS.bak" ]
  # The backup still holds the old value.
  [ "$(python3 -c "import json;print(json.load(open('$SETTINGS.bak'))['statusLine']['command'])")" = "my-custom-bar" ]
}

@test "setup: refuses to touch unparseable settings.json" {
  printf 'not json {{{' > "$SETTINGS"
  run env CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP"
  [ "$status" -eq 1 ]
  [[ "$output" == ERROR* ]]
  # Left exactly as it was.
  [ "$(cat "$SETTINGS")" = "not json {{{" ]
}

@test "setup: wires an explicit config dir as a quoted path, not a bare ~" {
  run env CLAUDE_CONFIG_DIR="$CFG" bash "$SETUP"
  [ "$status" -eq 0 ]
  [[ "$(cmd_field)" == "bash \"$CFG/statusline/statusline.sh\"" ]]
}
