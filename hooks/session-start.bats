#!/usr/bin/env bats
# Tests for hooks/session-start.sh — must remain project-agnostic.

HOOK="${BATS_TEST_DIRNAME}/session-start.sh"

setup() {
  TMP=$(mktemp -d)
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "session-start: runs without error in an empty git repo" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  run bash "$HOOK" <<<'{"session_event":"startup"}'
  [ "$status" -eq 0 ]
}

@test "session-start: does not print project-specific yamless/routo literals" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  run bash "$HOOK" <<<'{"session_event":"startup"}'
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qE 'yamless|routo|/Volumes/Projects/(routo|yamless)'
}

@test "session-start: runs without error outside any git repo" {
  cd /tmp
  run bash "$HOOK" <<<'{"session_event":"startup"}'
  [ "$status" -eq 0 ]
}

@test "session-start: emits per-toolchain doc only when toolchain detected" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  # No tsconfig, no Cargo.toml — neither block should appear.
  run bash "$HOOK" <<<'{"session_event":"startup"}'
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'TypeScript notes'
  ! echo "$output" | grep -q 'Rust notes'
}

@test "session-start: toolchain block stays off by default even when detected" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  # Track a tsconfig so detect_ts returns "ts", but omit CLAUDNESS_VERBOSE.
  echo '{}' > tsconfig.json
  git -c user.email=t@t -c user.name=t add tsconfig.json
  git -c user.email=t@t -c user.name=t commit -q -m ts
  unset CLAUDNESS_VERBOSE
  run bash "$HOOK" <<<'{"session_event":"startup"}'
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'TypeScript notes'
}

@test "session-start: toolchain block emits when CLAUDNESS_VERBOSE=1 and detected" {
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  echo '{}' > tsconfig.json
  git -c user.email=t@t -c user.name=t add tsconfig.json
  git -c user.email=t@t -c user.name=t commit -q -m ts
  export CLAUDNESS_VERBOSE=1
  run bash "$HOOK" <<<'{"session_event":"startup"}'
  unset CLAUDNESS_VERBOSE
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'TypeScript notes'
}
