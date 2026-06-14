#!/usr/bin/env bats
# Tests for the token-ledger Stop hook. Real (projected) transcript fixtures, no mocks.
# TZ pinned to UTC so the straddle fixture's week boundary is deterministic across
# machines (production uses the user's local TZ via jq strflocaltime).

HOOK="${BATS_TEST_DIRNAME}/../token-ledger.sh"
FIX="${BATS_TEST_DIRNAME}/../../__tests__/fixtures"

setup() {
  TMP=$(mktemp -d)
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# Run the hook with a transcript_path + session_id; TZ=UTC, isolated config dir.
_run_hook() {  # $1=transcript_path  $2=session_id
  printf '{"transcript_path":"%s","session_id":"%s"}' "$1" "$2" \
    | TZ=UTC CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$HOOK"
}

_tokens() {  # $1=week  $2=session_id -> prints .tokens (empty if file missing)
  jq -r '.tokens // empty' "$TMP/cfg/statusline/usage/$1/$2.json" 2>/dev/null
}

@test "token-ledger: dedups by message.id and excludes cache_read" {
  # dup.jsonl: 50 assistant lines / 25 distinct ids. naive(3-field)=358012, deduped=148517.
  # 148517 is small relative to a cache_read-inclusive sum, so this also proves exclusion.
  _run_hook "$FIX/dup.jsonl" s1
  [ "$(_tokens 2026-W24 s1)" = "148517" ]
}

@test "token-ledger: straddle splits tokens across weeks by message timestamp" {
  _run_hook "$FIX/straddle.jsonl" s1
  [ "$(_tokens 2026-W23 s1)" = "397944" ]
  [ "$(_tokens 2026-W24 s1)" = "389786" ]
}

@test "token-ledger: re-run is idempotent (token total stable)" {
  _run_hook "$FIX/dup.jsonl" s1
  first="$(_tokens 2026-W24 s1)"
  _run_hook "$FIX/dup.jsonl" s1
  second="$(_tokens 2026-W24 s1)"
  [ "$first" = "148517" ]
  [ "$second" = "148517" ]
}

@test "token-ledger: includes subagent transcripts in the weekly sum" {
  # main-only would be 56030; with the 3 sibling subagents/agent-*.jsonl it is 268219.
  _run_hook "$FIX/sub-session.jsonl" s1
  [ "$(_tokens 2026-W24 s1)" = "268219" ]
}

@test "token-ledger: missing transcript is a no-op, not an error" {
  run _run_hook "$TMP/does-not-exist.jsonl" s1
  [ "$status" -eq 0 ]
  [ ! -d "$TMP/cfg/statusline/usage" ]
}

@test "token-ledger: empty session_id writes nothing (no dotfile)" {
  run _run_hook "$FIX/dup.jsonl" ""
  [ "$status" -eq 0 ]
  [ ! -d "$TMP/cfg/statusline/usage" ]
}

@test "token-ledger: sanitizes session_id used as a path component" {
  _run_hook "$FIX/dup.jsonl" "a/b/../c"   # '/' and '.' stripped -> 'abc', no traversal
  [ "$(_tokens 2026-W24 abc)" = "148517" ]
  [ -z "$(find "$TMP/cfg/statusline/usage" -name '*..*' 2>/dev/null)" ]
}
