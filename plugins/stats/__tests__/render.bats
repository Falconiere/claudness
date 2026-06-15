#!/usr/bin/env bats
# render.sh — humanizers, text digest, --json. Aggregate is produced from
# crafted rollups (reusing aggregate.sh) so the digest reflects real shapes.

setup() {
  source "${BATS_TEST_DIRNAME}/../scripts/lib/aggregate.sh"
  source "${BATS_TEST_DIRNAME}/../scripts/lib/render.sh"
  TODAY="$(date +%Y-%m-%d)"
  full() { echo "{\"tokens\":$1,\"input\":$1,\"output\":0,\"cache_read\":0,\"cache_write\":0,\"cost\":$2}"; }
  ROLLUPS=$(cat <<EOF
[
 {"session_id":"sess-aaaa1111","project":"toolu.sh","project_path":"/Volumes/Projects/toolu.sh",
  "totals":$(full 1500000 4.20),
  "by_day":{"$TODAY":$(full 1500000 4.20)},
  "by_model":{"claude-opus-4-8":$(full 1500000 4.20)},
  "tools":{"Read":5,"Bash":2},"phases":{"execution":3}}
]
EOF
)
  AGG="$(echo "$ROLLUPS" | stats_aggregate)"
}

rnd() { echo "$AGG" | stats_render; }

@test "format_tokens humanizes M / k / raw" {
  [ "$(stats_format_tokens 13779513)" = "13.7M" ]
  [ "$(stats_format_tokens 45000)" = "45k" ]
  [ "$(stats_format_tokens 999)" = "999" ]
  [ "$(stats_format_tokens notanumber)" = "0" ]
}

@test "--json emits the raw aggregate, valid and complete" {
  export STATS_OUTPUT=json; run rnd; unset STATS_OUTPUT
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.totals.tokens == 1500000' >/dev/null
  echo "$output" | jq -e '.by_project[0].project_path == "/Volumes/Projects/toolu.sh"' >/dev/null
}

@test "text digest shows headline, windows, tables, activity" {
  run rnd
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Usage — 1.5M tokens"
  echo "$output" | grep -q "today"
  echo "$output" | grep -q "all-time"
  echo "$output" | grep -q "toolu.sh"
  echo "$output" | grep -q "claude-opus-4-8"
  echo "$output" | grep -q "Read:5"
  echo "$output" | grep -q "Bash:2"
  echo "$output" | grep -q "phases: execution:3"
  echo "$output" | grep -q "gate:"
}

@test "model-filtered aggregate renders windows as n/a" {
  export STATS_MODEL=opus; AGG="$(echo "$ROLLUPS" | stats_aggregate)"; unset STATS_MODEL
  run rnd
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "n/a under --model filter"
}

@test "empty usage degrades to a friendly notice" {
  AGG="$(echo '[]' | stats_aggregate)"
  run rnd
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no usage recorded"
}
