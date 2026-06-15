#!/usr/bin/env bats
# result.bats — writing a valid result, the mixed-mode abort, and required-key
# validation. Results land in a temp dir, never the repo.

setup() {
  BENCH_LIB="$BATS_TEST_DIRNAME/../lib"
  export BENCH_RESULTS_DIR="$BATS_TEST_TMPDIR/results"
}

# Write a complete, schema-valid retrieval result to $1; $2 sets the _modes array.
write_fixture() {
  local dest="$1" modes="$2"
  jq -nc --argjson modes "$modes" '{
    mechanism:"retrieval", tier:"deterministic", method:"tool-bytes",
    tokenizer:{mode:"heuristic", source:"bytes-div-4"},
    provenance:{model:null, date:"2026-06-14", commit:"abc123", n_runs:1, pricing_id:"2026-06"},
    baseline:{label:"full-read", tokens:{input:400,output:0,cache_read:0,cache_write:0,total:400}, cost:null},
    treatment:{label:"ast-grep", tokens:{input:80,output:0,cache_read:0,cache_write:0,total:80}, cost:null},
    delta:{tokens_pct:80, cost_pct:null, abs_tokens:320, mean:null, stddev:null},
    cases:[], notes:"",
    _modes:$modes
  }' > "$dest"
}

@test "writes a valid result and returns its path" {
  write_fixture "$BATS_TEST_TMPDIR/in.json" '["heuristic","heuristic"]'
  run bash -c 'source "$1/result.sh"; bench_result_write < "$2"' _ "$BENCH_LIB" "$BATS_TEST_TMPDIR/in.json"
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  [ "$(basename "$output")" = "retrieval-deterministic-2026-06-14.json" ]
  jq -e 'has("_modes") | not' "$output"            # transient field stripped
}

@test "mixed tokenizer modes are refused" {
  write_fixture "$BATS_TEST_TMPDIR/in.json" '["exact","heuristic"]'
  run bash -c 'source "$1/result.sh"; bench_result_write < "$2"' _ "$BENCH_LIB" "$BATS_TEST_TMPDIR/in.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mixed tokenizer modes"* ]]
}

@test "validate fails on a missing required key" {
  bad="$BATS_TEST_TMPDIR/bad.json"
  jq -n '{mechanism:"retrieval",tier:"deterministic",method:"tool-bytes",tokenizer:{mode:"heuristic",source:"bytes-div-4"},provenance:{model:null,date:"2026-06-14",commit:"abc",n_runs:1,pricing_id:"2026-06"},baseline:{label:"full-read",tokens:{total:400}},treatment:{label:"ast-grep",tokens:{total:80}},delta:{abs_tokens:320}}' > "$bad"
  run bash -c 'source "$1/result.sh"; bench_result_validate "$2"' _ "$BENCH_LIB" "$bad"
  [ "$status" -ne 0 ]
  [[ "$output" == *"delta.tokens_pct"* ]]
}

@test "validate passes on a written result" {
  write_fixture "$BATS_TEST_TMPDIR/in.json" '["heuristic","heuristic"]'
  out="$(bash -c 'source "$1/result.sh"; bench_result_write < "$2"' _ "$BENCH_LIB" "$BATS_TEST_TMPDIR/in.json")"
  run bash -c 'source "$1/result.sh"; bench_result_validate "$2"' _ "$BENCH_LIB" "$out"
  [ "$status" -eq 0 ]
}
