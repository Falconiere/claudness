#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/session-end.sh"

@test "session-end exits 0 with empty stdin" {
  run bash -c "'$SCRIPT' < /dev/null"
  [ "$status" -eq 0 ]
}

@test "session-end emits valid JSON with stopReason" {
  output=$(bash -c "'$SCRIPT' < /dev/null")
  echo "$output" | jq -e '.stopReason' >/dev/null
}

@test "session-end output does not leak source-repo names" {
  run bash -c "'$SCRIPT' < /dev/null"
  ! echo "$output" | grep -qE 'yamless|routo|/Volumes/Projects/(routo|yamless)'
}
