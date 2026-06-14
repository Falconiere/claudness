#!/usr/bin/env bats
# Tests for byte-savings-report.sh — aggregates a real ledger, no mocks.

setup() {
  TMP=$(mktemp -d)
  REPORT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/byte-savings-report.sh"
}

teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

@test "byte-savings-report: per-kind summary with Read saving% and totals" {
  led="$TMP/l.jsonl"
  printf '%s\n' \
    '{"kind":"read","returned":120,"full":4000}' \
    '{"kind":"grep","returned":300,"full":0}' \
    '{"kind":"ast-grep","returned":80,"full":0}' > "$led"
  run bash "$REPORT" "$led"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'read: returned=120 full=4000 saved=97% (n=1)'
  echo "$output" | grep -q 'grep: returned=300 (n=1)'
  echo "$output" | grep -q 'ast-grep: returned=80 (n=1)'
  echo "$output" | grep -q 'TOTAL returned: 500 bytes (~125 tok)'
}

@test "byte-savings-report: sums repeated kinds across a session" {
  led="$TMP/l.jsonl"
  printf '%s\n' \
    '{"kind":"read","returned":100,"full":1000}' \
    '{"kind":"read","returned":100,"full":1000}' > "$led"
  run bash "$REPORT" "$led"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'read: returned=200 full=2000 saved=90% (n=2)'
}

@test "byte-savings-report: missing ledger argument fails with usage" {
  run bash "$REPORT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'usage:'
}
