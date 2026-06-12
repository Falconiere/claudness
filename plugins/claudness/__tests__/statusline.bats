#!/usr/bin/env bats
# Tests for the claudness statusline. Real JSON payloads on stdin, no mocks.

SL="${BATS_TEST_DIRNAME}/../statusline.sh"

setup() {
  TMP=$(mktemp -d)
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# Strip ANSI colour codes so assertions match plain text.
_plain() { printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'; }

@test "statusline: renders model and context segments" {
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":200000,"total_input_tokens":45000,"used_percentage":22}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"Opus"* ]]
  [[ "$plain" == *"ctx:45k/200k (22%)"* ]]
}

@test "statusline: effort shown when present" {
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"effort:high"* ]]
}

@test "statusline: effort omitted when absent" {
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" != *"effort:"* ]]
}

@test "statusline: red gate marker when the project gate is failing" {
  mkdir -p "$TMP/.claude/tmp"
  printf '%s' '{"status":"failing","reason":"x"}' > "$TMP/.claude/tmp/quality-gate-status.json"
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$TMP"'"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"gate:failing"* ]]
}

@test "statusline: no gate marker when the gate is passing" {
  mkdir -p "$TMP/.claude/tmp"
  printf '%s' '{"status":"passing"}' > "$TMP/.claude/tmp/quality-gate-status.json"
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$TMP"'"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" != *"gate:failing"* ]]
}

@test "statusline: no gate marker when there is no gate file" {
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$TMP"'"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" != *"gate:failing"* ]]
}

@test "statusline: branch + folder shown for a git workspace" {
  ( cd "$TMP" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -qm init )
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$TMP"'"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"$(basename "$TMP")"* ]]
  # default branch name (main or master) appears
  [[ "$plain" == *"$(git -C "$TMP" symbolic-ref --short HEAD)"* ]]
}

@test "statusline: gate marker resolves via git root when cwd is a subdir" {
  ( cd "$TMP" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -qm init )
  mkdir -p "$TMP/.claude/tmp" "$TMP/packages/app/src"
  printf '%s' '{"status":"failing","reason":"x"}' > "$TMP/.claude/tmp/quality-gate-status.json"
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$TMP"'/packages/app/src"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"gate:failing"* ]]
}
