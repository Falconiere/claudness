#!/usr/bin/env bats
# Tests for project-detection helpers in hooks/lib/detect.sh.

setup() {
  LIB="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/detect.sh"
  TMP=$(mktemp -d)
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

@test "detect_project_name: returns 0 outside a git repo under set -e (fallback survives)" {
  # A bare `[ -n "$root" ] && basename` would exit 1 here and, under set -e,
  # abort a caller before its own fallback runs. The helper must exit 0.
  run bash -c 'set -euo pipefail; . "'"$LIB"'"; cd "'"$TMP"'"
    P="${X:-$(detect_project_name)}"; [ -z "$P" ] && P="unknown"; echo "name=[$P]"'
  [ "$status" -eq 0 ]
  [ "$output" = "name=[unknown]" ]
}

@test "detect_project_name: prints the toplevel basename inside a git repo" {
  git init -q "$TMP/myproj"
  run bash -c 'set -euo pipefail; . "'"$LIB"'"; cd "'"$TMP"'/myproj"; detect_project_name'
  [ "$status" -eq 0 ]
  [ "$output" = "myproj" ]
}
