#!/usr/bin/env bats
# pricing.sh — per-model cost math. Inputs are sized to 1e6 tokens so the
# expected $ equals the per-Mtok rate exactly (no float fuzz).

setup() {
  source "${BATS_TEST_DIRNAME}/../scripts/lib/pricing.sh"
}

# $1=model  $2=usage-json → cost in $
cost() {
  jq -nr --arg m "$1" --argjson u "$2" \
    "$(stats_pricing_jq) rates(\$m) as \$r | msgcost(\$u; \$r)"
}

@test "pricing_id is set" {
  [ -n "$STATS_PRICING_ID" ]
}

@test "opus prices input \$5 + output \$25 per Mtok" {
  run cost "claude-opus-4-8" '{"input_tokens":1000000,"output_tokens":1000000}'
  [ "$status" -eq 0 ]
  [ "$output" = "30" ]
}

@test "haiku prices input \$1 + output \$5 per Mtok" {
  run cost "claude-haiku-4-5-20251001" '{"input_tokens":1000000,"output_tokens":1000000}'
  [ "$output" = "6" ]
}

@test "unknown model falls back to sonnet \$3 input" {
  run cost "some-future-model" '{"input_tokens":1000000}'
  [ "$output" = "3" ]
}

@test "cache_read billed 0.1x input rate (opus)" {
  run cost "claude-opus-4-8" '{"cache_read_input_tokens":1000000}'
  [ "$output" = "0.5" ]
}

@test "cache write 5m TTL billed 1.25x input rate (opus)" {
  run cost "claude-opus-4-8" '{"cache_creation_input_tokens":1000000,"cache_creation":{"ephemeral_5m_input_tokens":1000000,"ephemeral_1h_input_tokens":0}}'
  [ "$output" = "6.25" ]
}

@test "cache write 1h TTL billed 2x input rate (opus)" {
  run cost "claude-opus-4-8" '{"cache_creation_input_tokens":1000000,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1000000}}'
  [ "$output" = "10" ]
}

@test "cache write falls back to 1.25x when no ephemeral split present" {
  run cost "claude-opus-4-8" '{"cache_creation_input_tokens":1000000}'
  [ "$output" = "6.25" ]
}
