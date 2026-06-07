#!/usr/bin/env bats
# Tests for hooks/post-tools/modules/rust-quality.sh

HOOK="${BATS_TEST_DIRNAME}/../rust-quality.sh"

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "rust-quality: no-op outside a Rust project (no Cargo.toml)" {
  payload='{"tool_input":{"file_path":"/nonexistent.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
