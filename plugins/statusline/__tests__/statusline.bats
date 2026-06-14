#!/usr/bin/env bats
# Tests for the toolu statusline. Real JSON payloads on stdin, no mocks.

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

@test "statusline: format_tokens M-tier renders millions with one decimal" {
  # format_tokens drives the ctx segment; feed a millions-scale token count.
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":200000,"total_input_tokens":13779513,"used_percentage":99}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"ctx:13.7M/200k"* ]]
}

@test "statusline: format_tokens M-tier stays k below a million" {
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":200000,"total_input_tokens":13779,"used_percentage":7}}' | bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"ctx:13k/200k"* ]]
}

@test "statusline: wk: renders the summed current-week usage dir" {
  wk=$(date +%G-W%V)
  mkdir -p "$TMP/cfg/statusline/usage/$wk"
  printf '{"tokens":1000000}' > "$TMP/cfg/statusline/usage/$wk/s1.json"
  printf '{"tokens":234567}'  > "$TMP/cfg/statusline/usage/$wk/s2.json"
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"wk:1.2M"* ]]
}

@test "statusline: wk: omitted when there is no usage for the week" {
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" != *"wk:"* ]]
}

@test "statusline: wk: a non-numeric usage file does not zero the whole week" {
  wk=$(date +%G-W%V)
  mkdir -p "$TMP/cfg/statusline/usage/$wk"
  printf '{"tokens":1000000}' > "$TMP/cfg/statusline/usage/$wk/good.json"
  printf '{"tokens":"abc"}'   > "$TMP/cfg/statusline/usage/$wk/bad.json"
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"wk:1.0M"* ]]
}

@test "statusline: comemory:renders the count from the comemory marker" {
  ( cd "$TMP" && git init -q )
  key=$(basename "$TMP")
  mkdir -p "$TMP/cfg/comemory-status"
  printf '{"repo":"%s","count":7}' "$key" > "$TMP/cfg/comemory-status/$key.json"
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$TMP"'"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"[COMEMORY:7]"* ]]
}

@test "statusline: comemory:worktree resolves to the main-repo key" {
  main="$TMP/main"; mkdir -p "$main"
  ( cd "$main" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -qm init )
  git -C "$main" worktree add -q "$TMP/wt" >/dev/null 2>&1
  key=$(basename "$main")
  mkdir -p "$TMP/cfg/comemory-status"
  printf '{"repo":"%s","count":5}' "$key" > "$TMP/cfg/comemory-status/$key.json"
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$TMP"'/wt"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" == *"[COMEMORY:5]"* ]]
}

@test "statusline: comemory:omitted when there is no marker" {
  ( cd "$TMP" && git init -q )
  out=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$TMP"'"},"context_window":{"context_window_size":200000,"total_input_tokens":1000}}' | CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$SL")
  plain=$(_plain "$out")
  [[ "$plain" != *"[COMEMORY:"* ]]
}
