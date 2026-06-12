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
  # A non-zero exit here is the collision signature: had the wrapper ALSO
  # injected its own --tags session-summary, comemory/clap would reject the
  # duplicate single-value flag and the save would fail. status 0 proves the
  # wrapper suppressed its default tag in favour of the caller's.
  run bash "$MOD" comemory summary "custom tagged summary" --tags "release,notes" --json
  [ "$status" -eq 0 ]
  local id
  id=$(echo "$output" | jq -r '.id')
  [ -n "$id" ]
  [ "$id" != "null" ]
  # The memory really persisted (the save was not silently partial).
  run bash "$MOD" comemory list --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"$id"* ]]
}

@test "comemory: wrapper injects --repo into the comemory invocation" {
  grep -q 'comemory search "\$query" --repo "\$REPO"' "$COMEMORY_SH"
  grep -q 'comemory save .* --repo "\$REPO"' "$COMEMORY_SH"
  grep -q 'comemory list --repo "\$REPO"' "$COMEMORY_SH"
}

@test "comemory: filter_project is gone from the wrapper" {
  ! grep -q 'filter_project' "$COMEMORY_SH"
}

# ── Code-intel verbs: repo-scoped (wrapper injects --repo) ─────────────────
@test "comemory: search-code/index-code/graph inject --repo" {
  grep -q 'comemory search-code "\$query" --repo "\$REPO"' "$COMEMORY_SH"
  grep -q 'comemory index-code --repo "\$REPO"' "$COMEMORY_SH"
  grep -q 'comemory graph --repo "\$REPO"' "$COMEMORY_SH"
}

@test "comemory: search-code runs against the real binary (lexical, empty index → no results, exit 0)" {
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/cm-sc"
  run bash "$MOD" comemory search-code "nonexistent_symbol_xyz"
  [ "$status" -eq 0 ]
}

# ── Retrieval-loop verbs: GLOBAL (must NOT inject --repo) ───────────────────
@test "comemory: global loop verbs exec without --repo injection" {
  # The combined branch forwards the subcommand verbatim — no --repo appended.
  grep -q 'mine|tune|eval|prune|gc|rebuild)' "$COMEMORY_SH"
  grep -q 'exec comemory "\$subcmd" "\$@"' "$COMEMORY_SH"
  # feedback forwards the positional query_id, also without --repo.
  grep -q 'exec comemory feedback "\$query_id" "\$@"' "$COMEMORY_SH"
  # No --repo anywhere on the global-verb lines.
  ! grep -E 'comemory (mine|tune|eval|prune|gc|rebuild|feedback).*--repo' "$COMEMORY_SH"
}

@test "comemory: maintain runs mine+prune+gc against the real binary (isolated store, exit 0)" {
  # Isolated data dir so prune --apply / gc never touch the real store.
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/cm-maint"
  mkdir -p "$COMEMORY_DATA_DIR"
  run bash "$MOD" comemory maintain
  [ "$status" -eq 0 ]
}

@test "comemory: feedback round-trips against the real binary (isolated store)" {
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/cm-fb"
  mkdir -p "$COMEMORY_DATA_DIR"
  # Save a memory, then search --json to obtain the query_id the loop feeds back.
  run bash "$MOD" comemory save "fb-title" "fb body content" --json
  [ "$status" -eq 0 ]
  local mem_id qid
  mem_id=$(echo "$output" | jq -r '.id')
  [ -n "$mem_id" ] && [ "$mem_id" != "null" ]
  run bash "$MOD" comemory search "fb-title" --json
  [ "$status" -eq 0 ]
  qid=$(echo "$output" | jq -r '.query_id // .queryId // empty')
  if [ -z "$qid" ]; then
    skip "comemory search --json did not expose a query_id field in this version"
  fi
  run bash "$MOD" comemory feedback "$qid" --used "$mem_id" --json
  [ "$status" -eq 0 ]
}
