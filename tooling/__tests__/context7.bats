#!/usr/bin/env bats
# Tests for .tooling/context7/search.sh env resolution.

load helpers

setup() {
  setup_sandbox context7
}

teardown() {
  teardown_sandbox
}

@test "context7: CONTEXT7_API_KEY in parent .env is sent as Bearer token" {
  write_env "CONTEXT7_API_KEY=ctx7sk_abc123"
  run "$TOOL_DIR/search.sh" search react
  [ "$status" -eq 0 ]
  grep -q '^Authorization: Bearer ctx7sk_abc123$' "$CURL_LOG"
}

@test "context7: missing .env runs in unauthenticated rate-limited mode" {
  # No env file — script must not exit, must not send Authorization header.
  run "$TOOL_DIR/search.sh" search react
  [ "$status" -eq 0 ]
  ! grep -q '^Authorization:' "$CURL_LOG"
}

@test "context7: non-ctx7sk-prefixed key is rejected (no Authorization header sent)" {
  write_env "CONTEXT7_API_KEY=garbage-prefix-key"
  run "$TOOL_DIR/search.sh" search react
  [ "$status" -eq 0 ]
  ! grep -q '^Authorization:' "$CURL_LOG"
}

@test "context7: search hits /libs/search with libraryName and query params" {
  write_env "CONTEXT7_API_KEY="
  run "$TOOL_DIR/search.sh" search tokio "async runtime"
  [ "$status" -eq 0 ]
  grep -q 'https://context7.com/api/v2/libs/search?libraryName=tokio&query=async%20runtime' "$CURL_LOG"
}

@test "context7: docs requires both library_id and query" {
  write_env "CONTEXT7_API_KEY="
  run "$TOOL_DIR/search.sh" docs
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "context7: help exits 1 with usage banner when no command given" {
  run "$TOOL_DIR/search.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Context7 CLI"* ]]
}

@test "context7: docs --fast appends fast=true to /v2/context request" {
  write_env "CONTEXT7_API_KEY="
  run "$TOOL_DIR/search.sh" docs /vercel/next.js "app router" --fast
  [ "$status" -eq 0 ]
  grep -q 'fast=true' "$CURL_LOG"
  # Slashes in libraryId are percent-encoded by the urlencode helper.
  grep -q 'libraryId=%2Fvercel%2Fnext.js' "$CURL_LOG"
}

@test "context7: docs without --fast omits the fast param entirely" {
  write_env "CONTEXT7_API_KEY="
  run "$TOOL_DIR/search.sh" docs /vercel/next.js "app router"
  [ "$status" -eq 0 ]
  ! grep -q 'fast=' "$CURL_LOG"
}

@test "context7: docs help advertises --fast flag (spec-compliant)" {
  run "$TOOL_DIR/search.sh" docs
  [ "$status" -eq 1 ]
  [[ "$output" == *"--fast"* ]]
}
