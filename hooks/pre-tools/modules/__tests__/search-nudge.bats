#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/../search-nudge.sh"

run_with() {
  local tool="$1" input="$2"
  tool_name="$tool" input="$input" bash "$SCRIPT"
}

@test "search-nudge: no-op on unrelated tool" {
  run run_with "Read" '{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "search-nudge: Grep with non-code glob allowed silently" {
  run run_with "Grep" '{"tool_input":{"pattern":"foo","glob":"*.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "search-nudge: Grep with structural pattern nudges to ast-grep" {
  run run_with "Grep" '{"tool_input":{"pattern":"fn handle_request","glob":"*.rs"}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("ast-grep")' >/dev/null
}

@test "search-nudge: Bash grep on structural pattern nudges to ast-grep" {
  run run_with "Bash" '{"tool_input":{"command":"grep -r \"impl Foo\" src"}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("ast-grep")' >/dev/null
}

@test "search-nudge: Bash without grep is silent" {
  run run_with "Bash" '{"tool_input":{"command":"ls -la"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "search-nudge: output does not leak source-repo names" {
  run run_with "Grep" '{"tool_input":{"pattern":"fn x"}}'
  ! echo "$output" | grep -qE 'yamless|routo|/Volumes/Projects/(routo|yamless)'
}

@test "search-nudge: sources lib from CLAUDNESS_LIB_DIR when set" {
  # Copy the module to a temp dir with NO ../../lib alongside it; only the
  # env var points at the real lib. Proves env-based sourcing works.
  tmp=$(mktemp -d)
  cp "${BATS_TEST_DIRNAME}/../search-nudge.sh" "$tmp/search-nudge.sh"
  run env CLAUDNESS_LIB_DIR="${BATS_TEST_DIRNAME}/../../../lib" \
    tool_name="Grep" input='{"tool_input":{"pattern":"fn handle_request","glob":"*.rs"}}' \
    bash "$tmp/search-nudge.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("ast-grep")' >/dev/null
  rm -rf "$tmp"
}
