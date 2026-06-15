#!/usr/bin/env bats
# tokens.bats — heuristic counting is hermetic; the never-downgrade abort is
# exercised against an unroutable endpoint; exact mode is key-gated (skips in CI).

setup() {
  BENCH_LIB="$BATS_TEST_DIRNAME/../lib"
}

@test "heuristic mode: bytes/4 when no API key" {
  ANTHROPIC_API_KEY="" run bash -c \
    'source "$1/tokens.sh"; printf "%s" "abcdefgh" | bench_count_tokens' _ "$BENCH_LIB"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tokens' <<<"$output")" -eq 2 ]      # 8 bytes / 4
  [ "$(jq -r '.mode'   <<<"$output")" = "heuristic" ]
  [ "$(jq -r '.source' <<<"$output")" = "bytes-div-4" ]
}

@test "abort (no silent downgrade) when key set but API unreachable" {
  ANTHROPIC_API_KEY="test-key" ANTHROPIC_BASE_URL="http://127.0.0.1:9" run bash -c \
    'source "$1/tokens.sh"; printf "%s" "hello" | bench_count_tokens' _ "$BENCH_LIB"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to downgrade"* ]]
}

@test "exact mode matches API input_tokens (key-gated)" {
  [ -n "${ANTHROPIC_API_KEY:-}" ] || skip "no ANTHROPIC_API_KEY"
  run bash -c 'source "$1/tokens.sh"; printf "%s" "The quick brown fox." | bench_count_tokens' _ "$BENCH_LIB"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.mode' <<<"$output")" = "exact" ]
  [ "$(jq -r '.tokens' <<<"$output")" -gt 0 ]
}

@test "unknown arg returns 2" {
  run bash -c 'source "$1/tokens.sh"; printf "x" | bench_count_tokens --bogus' _ "$BENCH_LIB"
  [ "$status" -eq 2 ]
}

@test "bench_stats: mean/stddev/n over real samples" {
  run bash -c 'source "$1/tokens.sh"; printf "10\n20\n30\n" | bench_stats' _ "$BENCH_LIB"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.mean'        <<<"$output")" = "20" ]
  [ "$(jq -r '.n'           <<<"$output")" -eq 3 ]
  [ "$(jq -r '.stddev|round' <<<"$output")" -eq 10 ]   # sample stddev of 10,20,30
}

@test "bench_stats: single sample has zero stddev" {
  run bash -c 'source "$1/tokens.sh"; printf "42\n" | bench_stats' _ "$BENCH_LIB"
  [ "$(jq -r '.mean'   <<<"$output")" = "42" ]
  [ "$(jq -r '.stddev' <<<"$output")" = "0" ]
  [ "$(jq -r '.n'      <<<"$output")" -eq 1 ]
}
