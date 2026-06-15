#!/usr/bin/env bats
# Tests for /comemory:setup (scripts/setup.sh) against the REAL comemory binary
# (no mocks for the READY path). The binary-state branches (MISSING/OLD/ERROR)
# are driven through the COMEMORY override seam — a stub or a bogus path — so
# coreutils stay on PATH and no package manager is ever invoked.

SETUP_SH="${BATS_TEST_DIRNAME}/../setup.sh"

# A tiny git repo with one indexable file + commit, plus an isolated data dir,
# so the READY path's install-hooks/index-code never touch the real store or a
# worktree (where `.git` is a file and install-hooks errors).
_make_repo() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git init -q "$REPO"
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  printf 'fn main() {}\n' > "$REPO/main.rs"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m init
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/data"
  mkdir -p "$COMEMORY_DATA_DIR"
}

# Write a fake `comemory` whose --version prints $1 (so we can force OLD/ERROR
# without an old real binary). Echoes the path to the stub.
_version_stub() {
  local ver="$1" dir="$BATS_TEST_TMPDIR/vstub-$BATS_TEST_NUMBER"
  mkdir -p "$dir"
  printf '#!/bin/sh\ncase "$1" in --version) echo "%s";; *) exit 0;; esac\n' "$ver" > "$dir/comemory"
  chmod +x "$dir/comemory"
  printf '%s\n' "$dir/comemory"
}

@test "setup: -h prints usage and exits 0" {
  run bash "$SETUP_SH" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: setup.sh"* ]]
}

@test "setup: MISSING when the binary is absent — prints the brew-tap install hint, exits 0" {
  run env COMEMORY=/nonexistent/comemory bash "$SETUP_SH"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk 'NR==1{print $1}')" = "MISSING" ]
  [[ "$output" == *"brew install Falconiere/tap/comemory"* ]]
  # never recommends the crates.io path that does not exist
  ! printf '%s\n' "$output" | grep -q 'cargo install comemory'
}

@test "setup: OLD when the binary is below the floor — prints the brew upgrade hint" {
  local stub
  stub=$(_version_stub "comemory 0.1.0")
  run env COMEMORY="$stub" bash "$SETUP_SH"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk 'NR==1{print $1}')" = "OLD" ]
  [[ "$output" == *"brew upgrade Falconiere/tap/comemory"* ]]
}

@test "setup: ERROR when the version string is unparseable — exits non-zero" {
  local stub
  stub=$(_version_stub "garbage-no-version")
  run env COMEMORY="$stub" bash "$SETUP_SH"
  [ "$status" -ne 0 ]
  [ "$(printf '%s' "$output" | awk 'NR==1{print $1}')" = "ERROR" ]
}

@test "setup: READY on the real binary wires install-hooks + index-code in a real repo" {
  command -v comemory >/dev/null 2>&1 || skip "comemory binary not installed"
  _make_repo
  cd "$REPO"
  run bash "$SETUP_SH"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk 'NR==1{print $1}')" = "READY" ]
  [[ "$output" == *"install-hooks: OK"* ]]
  [[ "$output" == *"index-code: OK"* ]]
  # The git hook really landed.
  [ -f "$REPO/.git/hooks/post-commit" ]
}

@test "setup: READY is idempotent — a second run still succeeds and re-reports" {
  command -v comemory >/dev/null 2>&1 || skip "comemory binary not installed"
  _make_repo
  cd "$REPO"
  run bash "$SETUP_SH"
  [ "$status" -eq 0 ]
  # Second run: install-hooks now refuses (hooks exist) but setup stays exit 0.
  run bash "$SETUP_SH"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk 'NR==1{print $1}')" = "READY" ]
}

@test "setup: READY outside a git repo skips hooks/index but still succeeds" {
  command -v comemory >/dev/null 2>&1 || skip "comemory binary not installed"
  export COMEMORY_DATA_DIR="$BATS_TEST_TMPDIR/data-nogit"
  mkdir -p "$COMEMORY_DATA_DIR"
  cd "$BATS_TEST_TMPDIR"   # a fresh temp dir — not a git repo
  run bash "$SETUP_SH"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk 'NR==1{print $1}')" = "READY" ]
  [[ "$output" == *"not in a git repo"* ]]
  [[ "$output" == *"install-hooks: skipped (not a git repo)"* ]]
  [[ "$output" == *"index-code: skipped (not a git repo)"* ]]
}

@test "setup: --force re-runs cleanly and overwrites existing hooks" {
  command -v comemory >/dev/null 2>&1 || skip "comemory binary not installed"
  _make_repo
  cd "$REPO"
  run bash "$SETUP_SH"
  [ "$status" -eq 0 ]
  run bash "$SETUP_SH" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"install-hooks: OK"* ]]
}
