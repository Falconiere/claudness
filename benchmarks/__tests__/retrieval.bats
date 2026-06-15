#!/usr/bin/env bats
# retrieval.bats — runs the deterministic retrieval bench over a STABLE fixture
# corpus (not volatile repo paths). Hermetic: forces heuristic counting, results
# to a temp dir. Covers the happy path and the missing-target guard.

setup() {
  BENCH_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"          # benchmarks/
  RUN="$BENCH_DIR/cases/retrieval/run.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
  export BENCH_RESULTS_DIR="$BATS_TEST_TMPDIR/results"
  export ANTHROPIC_API_KEY=""                               # force heuristic, no network
}

@test "produces a schema-valid result over the fixture corpus" {
  run bash "$RUN" --queries "$FIX/queries.tsv" --corpus "$FIX"
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  run bash -c 'source "$1/lib/result.sh"; bench_result_validate "$2"' _ "$BENCH_DIR" "$output"
  [ "$status" -eq 0 ]
}

@test "targeted query shows positive savings; counting is heuristic" {
  out="$(bash "$RUN" --queries "$FIX/queries.tsv" --corpus "$FIX")"
  [ "$(jq -r '.tokenizer.mode' "$out")" = "heuristic" ]
  [ "$(jq -r '.cases[] | select(.id=="target") | .saved' "$out")" -gt 0 ]
  [ "$(jq -r '.delta.tokens_pct' "$out")" -gt 0 ]
}

@test "missing target is guarded (saved 0 + note), no div-by-zero crash" {
  out="$(bash "$RUN" --queries "$FIX/queries.tsv" --corpus "$FIX")"
  [ "$(jq -r '.cases[] | select(.id=="missing") | .saved' "$out")" -eq 0 ]
  [ "$(jq -r '.cases[] | select(.id=="missing") | .note' "$out")" = "missing-or-empty-target" ]
  [[ "$(jq -r '.notes' "$out")" == *"missing-target"* ]]
}
