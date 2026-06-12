#!/usr/bin/env bats
# Round-trip tests for the comemory wrapper module against the REAL comemory
# binary (no mocks). Uses a unique throwaway --repo label so saved memories
# never collide with real project memories, and deletes everything it creates
# in teardown.

MOD="${BATS_TEST_DIRNAME}/../../mod.sh"
COMEMORY_SH="${BATS_TEST_DIRNAME}/../comemory.sh"

# Throwaway repo: the wrapper auto-detects the repo from the git toplevel, so
# we override it to a label nothing else uses.
TEST_REPO="claudness-mig-test"
export MY_CLAUDE_COMEMORY_REPO="$TEST_REPO"

setup() {
  command -v comemory >/dev/null 2>&1 || skip "comemory binary not installed"
}

teardown() {
  # Soft-delete every memory created under the throwaway repo. Tolerant of an
  # empty list and of a missing binary (setup skips, but teardown still runs).
  command -v comemory >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local id
  for id in $(comemory list --repo "$TEST_REPO" --json 2>/dev/null \
      | jq -r '.[].id' 2>/dev/null); do
    [ -n "$id" ] && comemory delete "$id" --json >/dev/null 2>&1 || true
  done
}

@test "comemory: save then search round-trips against the real binary" {
  # Save through the wrapper; --json (pass-through flag) emits {"id":...,"path":...}.
  run bash "$MOD" comemory save "mig-test-title" "mig-test real body" --json
  [ "$status" -eq 0 ]
  local id
  id=$(echo "$output" | jq -r '.id')
  [ -n "$id" ]
  [ "$id" != "null" ]

  # The saved memory's id must surface in the wrapper's search results.
  run bash "$MOD" comemory search "mig-test-title"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$id"* ]]
}

@test "comemory: summary saves a session-summary and accepts a --kind override without flag collision" {
  # summary must not hardcode --kind, so a caller-supplied --kind reaches
  # comemory cleanly (clap rejects a duplicate single-value flag).
  run bash "$MOD" comemory summary "wrapped up the migration" --kind decision --json
  [ "$status" -eq 0 ]
  local id
  id=$(echo "$output" | jq -r '.id')
  [ -n "$id" ]
  [ "$id" != "null" ]
  # The override landed: kind is the caller's value, not a forced default.
  run bash -c "comemory list --repo '$TEST_REPO' --json | jq -r '.[] | select(.id==\"$id\") | .kind'"
  [ "$status" -eq 0 ]
  [ "$output" = "decision" ]
}

@test "comemory: summary yields to a caller-supplied --tags without flag collision" {
  # When the caller passes --tags, the wrapper must NOT also inject its own.
  run bash "$MOD" comemory summary "custom tagged summary" --tags "release,notes" --json
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "comemory: wrapper injects --repo into the comemory invocation" {
  grep -q 'comemory search "\$query" --repo "\$REPO"' "$COMEMORY_SH"
  grep -q 'comemory save .* --repo "\$REPO"' "$COMEMORY_SH"
  grep -q 'comemory list --repo "\$REPO"' "$COMEMORY_SH"
}

@test "comemory: filter_project is gone from the wrapper" {
  ! grep -q 'filter_project' "$COMEMORY_SH"
}
