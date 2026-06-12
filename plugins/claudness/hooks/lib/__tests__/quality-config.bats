#!/usr/bin/env bats
# Tests for quality-config.sh — the threshold resolver. Real jq, real files,
# no mocks.

setup() {
  TMP=$(mktemp -d)
  export HOME="$TMP/home"
  export CLAUDE_PROJECT_DIR="$TMP/project"
  mkdir -p "$HOME/.claude" "$CLAUDE_PROJECT_DIR/.claude"
  ( cd "$CLAUDE_PROJECT_DIR" \
      && git init -q \
      && git -c user.email=t@t -c user.name=t commit --allow-empty -qm init )
  cd "$CLAUDE_PROJECT_DIR"
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# Source the libs in-process and point the config cache at a per-test file.
load_libs() {
  CLAUDNESS_LIB_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export CLAUDNESS_LIB_DIR
  # shellcheck disable=SC1091
  . "$CLAUDNESS_LIB_DIR/quality-config.sh"
  CLAUDNESS_CFG_CACHE="$TMP/cfg-cache.json"
  CLAUDNESS_CFG_LOADED=0
  _CLAUDNESS_HAS_JQ=""
}

_project_cfg() { printf '%s' "$1" > "$CLAUDE_PROJECT_DIR/.claude/claudness.config.json"; }
_user_cfg()    { printf '%s' "$1" > "$HOME/.claude/claudness.config.json"; }

@test "default when no config: TS 300, Rust 500/50/200" {
  load_libs
  run ts_max_file_lines;   [ "$output" = "300" ]
  run rust_max_file_lines; [ "$output" = "500" ]
  run rust_max_fn_lines;   [ "$output" = "50" ]
  run rust_max_impl_lines; [ "$output" = "200" ]
}

@test "project override wins over default" {
  _project_cfg '{"lang":{"ts":{"maxFileLines":120}}}'
  load_libs
  run ts_max_file_lines
  [ "$output" = "120" ]
}

@test "project override wins over eslint native config" {
  _project_cfg '{"lang":{"ts":{"maxFileLines":120}}}'
  printf '%s' '{"rules":{"max-lines":["error",250]}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "120" ]
}

@test "eslint max-lines as bare number" {
  printf '%s' '{"rules":{"max-lines":250}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "250" ]
}

@test "eslint max-lines as [error, N]" {
  printf '%s' '{"rules":{"max-lines":["error",240]}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "240" ]
}

@test "eslint max-lines as [error, {max: N}]" {
  printf '%s' '{"rules":{"max-lines":["error",{"max":222,"skipBlankLines":true}]}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "222" ]
}

@test "eslint max-lines off falls through to default" {
  printf '%s' '{"rules":{"max-lines":"off"}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "300" ]
}

@test "eslint max-lines [off, N] severity falls through to default" {
  printf '%s' '{"rules":{"max-lines":["off",250]}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "300" ]
}

@test "eslint max-lines [0, N] severity falls through to default" {
  printf '%s' '{"rules":{"max-lines":[0,250]}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "300" ]
}

@test "oxlint config used when no eslint config" {
  printf '%s' '{"rules":{"max-lines":["error",333]}}' > "$CLAUDE_PROJECT_DIR/.oxlintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "333" ]
}

@test "eslint takes precedence over oxlint" {
  printf '%s' '{"rules":{"max-lines":250}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  printf '%s' '{"rules":{"max-lines":333}}' > "$CLAUDE_PROJECT_DIR/.oxlintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "250" ]
}

@test "flat eslint config (JS) is skipped gracefully -> default" {
  printf '%s' 'export default [{ rules: { "max-lines": 200 } }]' > "$CLAUDE_PROJECT_DIR/eslint.config.mjs"
  load_libs
  run ts_max_file_lines
  [ "$status" -eq 0 ]
  [ "$output" = "300" ]
}

@test "malformed .eslintrc.json falls through to default, no error" {
  printf '%s' '{ broken' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$status" -eq 0 ]
  [ "$output" = "300" ]
}

@test "rust fn/impl never consult TS native config" {
  printf '%s' '{"rules":{"max-lines":["error",111]}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run rust_max_fn_lines;   [ "$output" = "50" ]
  run rust_max_file_lines; [ "$output" = "500" ]
}

@test "user vs project merge: project wins" {
  _user_cfg    '{"lang":{"ts":{"maxFileLines":111}}}'
  _project_cfg '{"lang":{"ts":{"maxFileLines":222}}}'
  load_libs
  run ts_max_file_lines
  [ "$output" = "222" ]
}

@test "zero / negative thresholds are rejected -> default" {
  _project_cfg '{"lang":{"ts":{"maxFileLines":0}}}'
  printf '%s' '{"rules":{"max-lines":["error",-5]}}' > "$CLAUDE_PROJECT_DIR/.eslintrc.json"
  load_libs
  run ts_max_file_lines
  [ "$output" = "300" ]
}

@test "rust project override works" {
  _project_cfg '{"lang":{"rust":{"maxFileLines":250,"maxFnLines":30,"maxImplLines":150}}}'
  load_libs
  run rust_max_file_lines; [ "$output" = "250" ]
  run rust_max_fn_lines;   [ "$output" = "30" ]
  run rust_max_impl_lines; [ "$output" = "150" ]
}
