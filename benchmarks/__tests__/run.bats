#!/usr/bin/env bats
# run.bats — the dispatcher: deterministic path writes a result, bad args fail
# with code 2, --validate passes through. Hermetic (heuristic counting, temp out).

setup() {
  BENCH_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUN="$BENCH_DIR/run.sh"
  export BENCH_RESULTS_DIR="$BATS_TEST_TMPDIR/results"
  export ANTHROPIC_API_KEY=""
}

@test "--tier deterministic runs retrieval and writes a result" {
  run bash "$RUN" --tier deterministic
  [ "$status" -eq 0 ]
  ls "$BENCH_RESULTS_DIR"/retrieval-deterministic-*.json
}

@test "unknown arg exits 2" {
  run bash "$RUN" --bogus
  [ "$status" -eq 2 ]
}

@test "bad --tier value exits 2" {
  run bash "$RUN" --tier nonsense
  [ "$status" -eq 2 ]
}

@test "--validate passes a good result and fails a bad one" {
  bash "$RUN" --tier deterministic
  good="$(ls "$BENCH_RESULTS_DIR"/retrieval-deterministic-*.json | head -1)"
  run bash "$RUN" --validate "$good"
  [ "$status" -eq 0 ]

  bad="$BATS_TEST_TMPDIR/bad.json"
  echo '{"mechanism":"retrieval"}' > "$bad"
  run bash "$RUN" --validate "$bad"
  [ "$status" -ne 0 ]
}

@test "--help exits 0" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
}
