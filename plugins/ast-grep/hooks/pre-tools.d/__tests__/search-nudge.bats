#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/../search-nudge.sh"

# Core lib lives in the sibling toolu plugin; the dispatcher provides
# this env var in production, the tests provide it here.
TOOLU_LIB_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../toolu/hooks/lib" && pwd)"
export TOOLU_LIB_DIR

teardown() {
  # Cleans the env-sourcing test's tempdir even when an assertion fails.
  if [ -n "${tmp:-}" ] && [ -d "$tmp" ]; then rm -rf "$tmp"; fi
}

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

@test "search-nudge: sources lib from TOOLU_LIB_DIR when set" {
  # Copy the module to a temp dir with NO ../../lib alongside it; only the
  # env var points at the real lib. Proves env-based sourcing works.
  tmp=$(mktemp -d)
  cp "${BATS_TEST_DIRNAME}/../search-nudge.sh" "$tmp/search-nudge.sh"
  run env TOOLU_LIB_DIR="${BATS_TEST_DIRNAME}/../../../../toolu/hooks/lib" \
    tool_name="Grep" input='{"tool_input":{"pattern":"fn handle_request","glob":"*.rs"}}' \
    bash "$tmp/search-nudge.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("ast-grep")' >/dev/null
}

@test "search-nudge: exits 0 silently when TOOLU_LIB_DIR is unset (fail soft)" {
  run env -u TOOLU_LIB_DIR \
    tool_name="Grep" input='{"tool_input":{"pattern":"fn handle_request","glob":"*.rs"}}' \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
