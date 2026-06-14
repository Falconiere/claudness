#!/usr/bin/env bats
# Tests for hooks/lib/gate-file.sh — the multi-slot quality-gate writer.

setup() {
  TMP=$(mktemp -d)
  GATE="$TMP/quality-gate-status.json"
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  # shellcheck source=../gate-file.sh
  . "$REPO_ROOT/hooks/lib/gate-file.sh"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

@test "gate-file: first failure writes failing with one entry" {
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad" "viol-a\n"
  jq -e '.status == "failing"' "$GATE"
  jq -e '.source == "ts-quality-hook"' "$GATE"
  jq -e '.file == "/p/a.ts"' "$GATE"
  jq -e '.entries | length == 1' "$GATE"
}

@test "gate-file: second file's failure does not clobber the first" {
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad ts" "viol-a\n"
  gate_record_failure "$GATE" "/p/b.rs" "rust-quality-hook" "bad rust" "viol-b\n"
  jq -e '.entries | length == 2' "$GATE"
  jq -e '.entries["/p/a.ts"].source == "ts-quality-hook"' "$GATE"
  jq -e '.entries["/p/b.rs"].source == "rust-quality-hook"' "$GATE"
  # Top level mirrors the most recent failure; violations aggregate both.
  jq -e '.file == "/p/b.rs"' "$GATE"
  grep -q 'viol-a' "$GATE"
  grep -q 'viol-b' "$GATE"
}

@test "gate-file: clearing one entry keeps the gate failing on the other" {
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad ts" "viol-a\n"
  gate_record_failure "$GATE" "/p/b.rs" "rust-quality-hook" "bad rust" "viol-b\n"
  gate_clear_file "$GATE" "/p/b.rs" "rust-quality-hook"
  jq -e '.status == "failing"' "$GATE"
  # The surviving entry is promoted back to the top level.
  jq -e '.source == "ts-quality-hook"' "$GATE"
  jq -e '.file == "/p/a.ts"' "$GATE"
  jq -e '.reason == "bad ts"' "$GATE"
  jq -e '.entries | length == 1' "$GATE"
}

@test "gate-file: clearing the last entry flips the gate to passing" {
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad ts" "viol-a\n"
  gate_clear_file "$GATE" "/p/a.ts" "ts-quality-hook"
  jq -e '.status == "passing"' "$GATE"
  jq -e 'has("entries") | not' "$GATE"
}

@test "gate-file: clear is a no-op when the source does not own the entry" {
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad ts" "viol-a\n"
  before=$(cat "$GATE")
  gate_clear_file "$GATE" "/p/a.ts" "rust-quality-hook"
  [ "$(cat "$GATE")" = "$before" ]
}

@test "gate-file: legacy single-slot failing record is seeded, not clobbered" {
  jq -n '{status: "failing", reason: "Quality command failed: bun test (exit 1)",
          source: "gate-status-hook", updatedAt: "2026-01-01T00:00:00Z"}' > "$GATE"
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad ts" "viol-a\n"
  jq -e '.entries | length == 2' "$GATE"
  jq -e '.entries["__global__"].source == "gate-status-hook"' "$GATE"
  # Clearing the ts entry must promote the seeded command failure, not pass.
  gate_clear_file "$GATE" "/p/a.ts" "ts-quality-hook"
  jq -e '.status == "failing"' "$GATE"
  jq -e '.source == "gate-status-hook"' "$GATE"
  jq -e '.reason | startswith("Quality command failed")' "$GATE"
}

@test "gate-file: legacy passing record does not seed a ghost entry" {
  jq -n '{status: "passing", source: "bun test", updatedAt: "2026-01-01T00:00:00Z"}' > "$GATE"
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad ts" "viol-a\n"
  jq -e '.entries | length == 1' "$GATE"
  gate_clear_file "$GATE" "/p/a.ts" "ts-quality-hook"
  jq -e '.status == "passing"' "$GATE"
}

@test "gate-file: malformed existing JSON is replaced, failure still recorded" {
  printf '{ broken' > "$GATE"
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad ts" "viol-a\n"
  jq -e '.status == "failing"' "$GATE"
  jq -e '.entries | length == 1' "$GATE"
}

@test "gate-file: clear on a missing or passing gate file is a no-op" {
  gate_clear_file "$GATE" "/p/a.ts" "ts-quality-hook"
  [ ! -f "$GATE" ]
  jq -n '{status: "passing", source: "bun test"}' > "$GATE"
  before=$(cat "$GATE")
  gate_clear_file "$GATE" "/p/a.ts" "ts-quality-hook"
  [ "$(cat "$GATE")" = "$before" ]
}

@test "gate-file: re-recording the same file replaces its entry, not duplicates" {
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad ts" "viol-1\n"
  gate_record_failure "$GATE" "/p/a.ts" "ts-quality-hook" "bad ts" "viol-2\n"
  jq -e '.entries | length == 1' "$GATE"
  grep -q 'viol-2' "$GATE"
  ! grep -q 'viol-1' "$GATE"
}
