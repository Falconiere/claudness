#!/usr/bin/env bats
# Round-trip tests for the comemory wrapper module against the REAL comemory
# binary (no mocks). Uses a unique throwaway --repo label so saved memories
# never collide with real project memories, and deletes everything it creates
# in teardown.

COMEMORY_SH="${BATS_TEST_DIRNAME}/../comemory.sh"

# Throwaway repo: the wrapper auto-detects the repo from the git toplevel, so
# we override it to a label nothing else uses.
TEST_REPO="toolu-mig-test"
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
  run bash "$COMEMORY_SH" save "mig-test-title" "mig-test real body" --json
  [ "$status" -eq 0 ]
  local id
  id=$(echo "$output" | jq -r '.id')
  [ -n "$id" ]
  [ "$id" != "null" ]

  # The saved memory's id must surface in the wrapper's search results.
  run bash "$COMEMORY_SH" search "mig-test-title"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$id"* ]]
}

@test "comemory: summary saves a session-summary and accepts a --kind override without flag collision" {
  # summary must not hardcode --kind, so a caller-supplied --kind reaches
  # comemory cleanly (clap rejects a duplicate single-value flag).
  run bash "$COMEMORY_SH" summary "wrapped up the migration" --kind decision --json
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
  run bash "$COMEMORY_SH" summary "custom tagged summary" --tags "release,notes" --json
  [ "$status" -eq 0 ]
  local id
  id=$(echo "$output" | jq -r '.id')
  [ -n "$id" ]
  [ "$id" != "null" ]
  # The memory really persisted (the save was not silently partial).
  run bash "$COMEMORY_SH" list --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"$id"* ]]
}

# A stub `comemory` on PATH echoes its argv one-per-line, so these assert the
# EXACT argv the wrapper builds (behavioral) rather than grepping wrapper source.
_stub_argv() {
  STUB="$BATS_TEST_TMPDIR/argv-stub"
  mkdir -p "$STUB"
  printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' > "$STUB/comemory"
  chmod +x "$STUB/comemory"
}

@test "comemory: wrapper injects --repo <repo> and guards the positional with -- (behavioral argv)" {
  _stub_argv
  run env PATH="$STUB:$PATH" MY_CLAUDE_COMEMORY_REPO=behave bash "$COMEMORY_SH" search "hello"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cx -- '--repo')" -eq 1 ]
  printf '%s\n' "$output" | grep -qx 'behave'
  printf '%s\n' "$output" | grep -qx -- '--'      # end-of-options guard present
  printf '%s\n' "$output" | grep -qx 'hello'      # query passed as positional
}

@test "comemory: caller --repo suppresses the wrapper's injection — no duplicate (behavioral argv)" {
  _stub_argv
  run env PATH="$STUB:$PATH" MY_CLAUDE_COMEMORY_REPO=behave bash "$COMEMORY_SH" search "hi" --repo caller
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cx -- '--repo')" -eq 1 ]
  printf '%s\n' "$output" | grep -qx 'caller'
  ! printf '%s\n' "$output" | grep -qx 'behave'
}

@test "comemory: search-code/index-code/graph carry --repo (behavioral argv)" {
  _stub_argv
  run env PATH="$STUB:$PATH" MY_CLAUDE_COMEMORY_REPO=behave bash "$COMEMORY_SH" search-code "sym"
  [ "$status" -eq 0 ]; printf '%s\n' "$output" | grep -qx -- '--repo'; printf '%s\n' "$output" | grep -qx 'behave'
  run env PATH="$STUB:$PATH" MY_CLAUDE_COMEMORY_REPO=behave bash "$COMEMORY_SH" graph
  [ "$status" -eq 0 ]; printf '%s\n' "$output" | grep -qx -- '--repo'
  run env PATH="$STUB:$PATH" MY_CLAUDE_COMEMORY_REPO=behave bash "$COMEMORY_SH" index-code --path /tmp/x
  [ "$status" -eq 0 ]; printf '%s\n' "$output" | grep -qx -- '--repo'
}

@test "comemory: filter_project is gone from the wrapper" {
  ! grep -q 'filter_project' "$COMEMORY_SH"
}

@test "comemory: save with a leading-dash title is not parsed as a flag (real binary)" {
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/cm-dash"
  run bash "$COMEMORY_SH" save "--dashy-title" "real body" --json
  [ "$status" -eq 0 ]
  local id
  id=$(echo "$output" | jq -r '.id')
  [ -n "$id" ] && [ "$id" != "null" ]
}

@test "comemory: search-code runs against the real binary (lexical, empty index → no results, exit 0)" {
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/cm-sc"
  run bash "$COMEMORY_SH" search-code "nonexistent_symbol_xyz"
  [ "$status" -eq 0 ]
}

# ── Retrieval-loop verbs: GLOBAL (must NOT inject --repo) ───────────────────
@test "comemory: global loop verbs exec without --repo injection" {
  # The combined branch forwards the subcommand verbatim — no --repo appended.
  grep -q 'mine|tune|eval|prune|gc|rebuild)' "$COMEMORY_SH"
  grep -q 'exec comemory "\$subcmd" "\$@"' "$COMEMORY_SH"
  # feedback forwards the positional query_id after the -- guard, still no --repo.
  grep -q 'exec comemory feedback "\$@" -- "\$query_id"' "$COMEMORY_SH"
  # No --repo anywhere on the global-verb lines.
  ! grep -E 'comemory (mine|tune|eval|prune|gc|rebuild|feedback).*--repo' "$COMEMORY_SH"
}

@test "comemory: maintain runs mine+prune+gc against the real binary (isolated store, exit 0)" {
  # Isolated data dir so prune --apply / gc never touch the real store.
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/cm-maint"
  mkdir -p "$COMEMORY_DATA_DIR"
  run bash "$COMEMORY_SH" maintain
  [ "$status" -eq 0 ]
}

@test "comemory: caller-supplied --repo overrides without a clap duplicate-flag collision" {
  # The wrapper must NOT also inject --repo when the caller passed one; a second
  # --repo would clap-collide and exit non-zero.
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/cm-repo"
  run bash "$COMEMORY_SH" save "ovr-title" "ovr body" --repo custom-scope --json
  [ "$status" -eq 0 ]
  local id
  id=$(echo "$output" | jq -r '.id')
  [ -n "$id" ] && [ "$id" != "null" ]
  # It landed under the caller's repo, not the auto-detected default.
  run bash -c "comemory list --repo custom-scope --json | jq -r '.[].id'"
  [[ "$output" == *"$id"* ]]
}

@test "comemory: flag-like MY_CLAUDE_COMEMORY_REPO falls back to unknown (no flag injection)" {
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/cm-flag"
  MY_CLAUDE_COMEMORY_REPO="-evil" run bash "$COMEMORY_SH" list --json
  [ "$status" -eq 0 ]
}

# ── Worktree scope: --repo must be the REPO, not the per-worktree checkout dir ─
# Regression: detect_project_root used `git rev-parse --show-toplevel`, which in
# a worktree is the worktree dir — so saves made in a worktree got an orphan
# `--repo <worktree-name>` scope, invisible from main and sibling worktrees.
# Build a REAL repo + worktree (no mocks for git) and capture the injected
# --repo via the argv stub so the real store is untouched.
_make_repo_with_worktree() {
  REPO_DIR="$BATS_TEST_TMPDIR/myrepo"
  WT_DIR="$BATS_TEST_TMPDIR/wt-feature"
  git init -q "$REPO_DIR"
  git -C "$REPO_DIR" config user.email t@t.t
  git -C "$REPO_DIR" config user.name t
  git -C "$REPO_DIR" commit -q --allow-empty -m init
  git -C "$REPO_DIR" worktree add -q "$WT_DIR" >/dev/null 2>&1
}

@test "comemory: --repo resolves to the repo name from inside a git worktree (real worktree, argv stub)" {
  _stub_argv
  _make_repo_with_worktree
  # MY_CLAUDE_COMEMORY_REPO is exported suite-wide; unset it so auto-detection runs.
  cd "$WT_DIR"
  run env -u MY_CLAUDE_COMEMORY_REPO PATH="$STUB:$PATH" bash "$COMEMORY_SH" search "hi"
  [ "$status" -eq 0 ]
  local repo_val
  repo_val=$(printf '%s\n' "$output" | awk '/^--repo$/{getline; print; exit}')
  [ "$repo_val" = "myrepo" ]        # the repo, shared across worktrees
  [ "$repo_val" != "wt-feature" ]   # NOT the per-worktree checkout dir
}

@test "comemory: --repo matches between the main checkout and its worktree (real worktree, argv stub)" {
  _stub_argv
  _make_repo_with_worktree
  cd "$REPO_DIR"
  run env -u MY_CLAUDE_COMEMORY_REPO PATH="$STUB:$PATH" bash "$COMEMORY_SH" search "hi"
  [ "$status" -eq 0 ]
  local from_main
  from_main=$(printf '%s\n' "$output" | awk '/^--repo$/{getline; print; exit}')
  cd "$WT_DIR"
  run env -u MY_CLAUDE_COMEMORY_REPO PATH="$STUB:$PATH" bash "$COMEMORY_SH" search "hi"
  [ "$status" -eq 0 ]
  local from_wt
  from_wt=$(printf '%s\n' "$output" | awk '/^--repo$/{getline; print; exit}')
  [ "$from_main" = "myrepo" ]
  [ "$from_wt" = "$from_main" ]
}

@test "comemory: feedback round-trips against the real binary (isolated store)" {
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/cm-fb"
  mkdir -p "$COMEMORY_DATA_DIR"
  # Save a memory, then search --json to obtain the query_id the loop feeds back.
  run bash "$COMEMORY_SH" save "fb-title" "fb body content" --json
  [ "$status" -eq 0 ]
  local mem_id qid
  mem_id=$(echo "$output" | jq -r '.id')
  [ -n "$mem_id" ] && [ "$mem_id" != "null" ]
  run bash "$COMEMORY_SH" search "fb-title" --json
  [ "$status" -eq 0 ]
  qid=$(echo "$output" | jq -r '.query_id // .queryId // empty')
  if [ -z "$qid" ]; then
    skip "comemory search --json did not expose a query_id field in this version"
  fi
  run bash "$COMEMORY_SH" feedback "$qid" --used "$mem_id" --json
  [ "$status" -eq 0 ]
}
