#!/usr/bin/env bats
# Tests for the byte-savings PostToolUse instrumentation module. Real payloads,
# real files on disk, no mocks — the module measures actual bytes.

setup() {
  TMP=$(mktemp -d)
  MOD="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/byte-savings.sh"
}

teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

@test "byte-savings: records returned + full bytes for a single-file Read" {
  f="$TMP/src.txt"; printf 'x%.0s' {1..4000} > "$f"   # a real 4000-byte file
  payload=$(jq -n --arg fp "$f" '{session_id:"s1",tool_input:{file_path:$fp},tool_response:"hello"}')
  run env tool_name=Read input="$payload" CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$MOD"
  [ "$status" -eq 0 ]
  led="$TMP/cfg/toolu/byte-savings/s1.jsonl"
  [ -f "$led" ]
  [ "$(jq -r '.kind'     "$led")" = "read" ]
  [ "$(jq -r '.returned' "$led")" = "5" ]      # "hello"
  [ "$(jq -r '.full'     "$led")" = "4000" ]
}

@test "byte-savings: records ast-grep Bash result bytes (full=0, no counterfactual)" {
  payload=$(jq -n '{session_id:"s2",tool_input:{command:"ast-grep run --pattern foo ."},tool_response:{stdout:"match line"}}')
  run env tool_name=Bash input="$payload" CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$MOD"
  [ "$status" -eq 0 ]
  led="$TMP/cfg/toolu/byte-savings/s2.jsonl"
  [ "$(jq -r '.kind'     "$led")" = "ast-grep" ]
  [ "$(jq -r '.returned' "$led")" = "10" ]     # "match line"
  [ "$(jq -r '.full'     "$led")" = "0" ]
}

@test "byte-savings: unrelated tools write no ledger" {
  payload=$(jq -n '{session_id:"s3",tool_input:{},tool_response:"x"}')
  run env tool_name=Edit input="$payload" CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$MOD"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/cfg/toolu/byte-savings/s3.jsonl" ]
}

@test "byte-savings: a plain (non-ast-grep) Bash command is ignored" {
  payload=$(jq -n '{session_id:"s4",tool_input:{command:"ls -la"},tool_response:{stdout:"files"}}')
  run env tool_name=Bash input="$payload" CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$MOD"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/cfg/toolu/byte-savings/s4.jsonl" ]
}

@test "byte-savings: a Read of a missing file records full=0 (no fabrication)" {
  payload=$(jq -n '{session_id:"s5",tool_input:{file_path:"/no/such/file"},tool_response:"abc"}')
  run env tool_name=Read input="$payload" CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$MOD"
  [ "$status" -eq 0 ]
  led="$TMP/cfg/toolu/byte-savings/s5.jsonl"
  [ "$(jq -r '.returned' "$led")" = "3" ]
  [ "$(jq -r '.full'     "$led")" = "0" ]
}
