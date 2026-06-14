#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/../pre-compact.sh"

@test "pre-compact exits 0 with empty stdin" {
  run bash -c "'$SCRIPT' < /dev/null"
  [ "$status" -eq 0 ]
}

@test "pre-compact emits valid JSON" {
  output=$(bash -c "'$SCRIPT' < /dev/null")
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreCompact"' >/dev/null
}

@test "pre-compact output does not leak source-repo names" {
  run bash -c "'$SCRIPT' < /dev/null"
  ! echo "$output" | grep -qE 'yamless|routo|/Volumes/Projects/(routo|yamless)'
}
