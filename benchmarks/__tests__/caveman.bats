#!/usr/bin/env bats
# caveman.bats — HERMETIC: the caveman case is a LIVE tier (needs a real API key +
# network), so these tests never call the API. They assert the static artifacts
# exist, the no-key path aborts with a useful message, and a hand-built caveman
# result mirroring the live schema passes bench_result_validate. Results land in a
# temp dir, never the repo.

setup() {
  BENCH_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"          # benchmarks/
  CASE="$BENCH_DIR/cases/caveman"
  RUN="$CASE/run.sh"
  export BENCH_RESULTS_DIR="$BATS_TEST_TMPDIR/results"
}

@test "static artifacts exist" {
  [ -f "$CASE/baseline-system.txt" ]
  [ -s "$CASE/baseline-system.txt" ]
  [ -f "$CASE/treatment-system.txt" ]
  [ -s "$CASE/treatment-system.txt" ]
  [ -f "$CASE/SOURCE.md" ]
  [ -d "$CASE/prompts" ]
  [ -x "$RUN" ]
}

@test "prompts/ has at least one non-empty .txt prompt" {
  local count=0 f
  for f in "$CASE"/prompts/*.txt; do
    [ -s "$f" ] && count=$((count + 1))
  done
  [ "$count" -ge 1 ]
}

@test "no API key aborts with a message naming ANTHROPIC_API_KEY" {
  ANTHROPIC_API_KEY="" run bash "$RUN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ANTHROPIC_API_KEY"* ]]
}

@test "unknown arg exits 2 (before any key/network check)" {
  ANTHROPIC_API_KEY="" run bash "$RUN" --bogus
  [ "$status" -eq 2 ]
}

@test "a hand-built caveman result mirroring the live schema validates" {
  local in="$BATS_TEST_TMPDIR/in.json"
  jq -nc '{
    mechanism:"caveman", tier:"live", method:"api-ab",
    tokenizer:{mode:"usage", source:"usage"},
    provenance:{model:"claude-sonnet-4-6", date:"2026-06-15",
                commit:"deadbeef", n_runs:5, pricing_id:"2026-06"},
    baseline:{label:"answer-concisely",
              tokens:{input:0, output:240, cache_read:0, cache_write:0, total:240},
              cost:null},
    treatment:{label:"caveman",
               tokens:{input:0, output:150, cache_read:0, cache_write:0, total:150},
               cost:null},
    delta:{tokens_pct:38, cost_pct:null, abs_tokens:90, mean:150, stddev:12},
    cases:[{id:"howto-pg-index", baseline_tokens:240, treatment_tokens:150}],
    notes:"",
    _modes:["usage","usage"]
  }' > "$in"

  run bash -c 'source "$1/lib/result.sh"; bench_result_write < "$2"' _ "$BENCH_DIR" "$in"
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  [ "$(basename "$output")" = "caveman-live-2026-06-15.json" ]

  run bash -c 'source "$1/lib/result.sh"; bench_result_validate "$2"' _ "$BENCH_DIR" "$output"
  [ "$status" -eq 0 ]
}

@test "stubbed-API run drives the real emit pipeline to a schema-valid result" {
  # Stub ONLY the network boundary: a fake `curl` returning a real /v1/messages
  # response shape. Everything downstream is the REAL code under test — output
  # token parsing, bench_stats, the jq emit, bench_result_write + validation.
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  cat > "$bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s' '{"id":"msg_x","type":"message","role":"assistant","usage":{"input_tokens":40,"output_tokens":17}}'
STUB
  chmod +x "$bin/curl"

  PATH="$bin:$PATH" ANTHROPIC_API_KEY="test-key" run bash "$RUN" --n 2
  [ "$status" -eq 0 ]
  local out
  out="$(ls "$BENCH_RESULTS_DIR"/caveman-live-*.json | head -1)"
  [ -f "$out" ]
  [ "$(jq -r '.mechanism'        "$out")" = "caveman" ]
  [ "$(jq -r '.tier'             "$out")" = "live" ]
  [ "$(jq -r '.tokenizer.mode'   "$out")" = "usage" ]
  [ "$(jq -r '.provenance.n_runs' "$out")" -gt 0 ]

  run bash -c 'source "$1/lib/result.sh"; bench_result_validate "$2"' _ "$BENCH_DIR" "$out"
  [ "$status" -eq 0 ]
}
