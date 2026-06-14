#!/usr/bin/env bats
# Covers the rust-quality 90-docs concern: a public API item in src/ without a
# /// doc comment emits a NON-BLOCKING docs advisory (no gate failure), for both
# bare `pub fn` and restricted `pub(crate) fn` visibility. Drives the ASSEMBLED
# registry module assembled by register.sh.

# Core lib lives in the sibling claudness plugin; the dispatcher provides this
# env var in production, the tests provide it here.
CLAUDNESS_LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../claudness/hooks/lib" && pwd)"
export CLAUDNESS_LIB_DIR

setup() {
  TMP=$(mktemp -d)

  export CLAUDE_CONFIG_DIR="$TMP/cfg"
  REGISTER="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/register.sh"
  bash "$REGISTER" </dev/null
  HOOK="$CLAUDE_CONFIG_DIR/claudness/post-tools.d/rust-quality@falconiere__rust-quality.sh"

  TMP_PROJ="$TMP/proj"
  mkdir -p "$TMP_PROJ"
  cd "$TMP_PROJ"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

_rust_project() {
  printf '[package]\nname = "x"\nversion = "0.1.0"\n' > Cargo.toml
  mkdir -p src
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m setup
}

# Regression: the docs advisory matched only bare `pub (fn|struct|enum|trait)`,
# so `pub(crate)` / `pub(super)` visibility and pub const/static/type/mod were
# silently skipped. The broadened regex covers them.
@test "rust-quality: pub(crate) fn without /// doc emits a docs advisory" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/api.rs <<'EOF'
pub(crate) fn do_thing() -> u32 {
    1
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP_PROJ"'/src/api.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP_PROJ" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "missing a /// doc"
  ! echo "$output" | grep -q "QUALITY VIOLATION"
}

@test "rust-quality: pub fn without /// doc emits a non-blocking docs advisory" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/api.rs <<'EOF'
pub fn do_thing() -> u32 {
    1
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP_PROJ"'/src/api.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP_PROJ" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "missing a /// doc"
  ! echo "$output" | grep -q "QUALITY VIOLATION"
}
