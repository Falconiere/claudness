#!/usr/bin/env bats
# Covers the rust-quality 40-unsafe concern: an unsafe block/fn in src/ is
# flagged, while `unsafe {` appearing only inside a // line comment or a
# multi-line /* */ block comment is stripped before matching (no false
# positive). Drives the ASSEMBLED registry module assembled by register.sh.

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

@test "rust-quality: unsafe block in src/ is flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/u.rs <<'EOF'
pub fn f() {
    unsafe {
        do_thing();
    }
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP_PROJ"'/src/u.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP_PROJ" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Forbidden unsafe code"
}

# Regression: the rule used a raw grep, so `unsafe {` inside a comment
# false-positived. It now strips comments before matching.
@test "rust-quality: unsafe mentioned only in a comment is NOT flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/ok.rs <<'EOF'
// we deliberately avoid unsafe { } here; use safe wrappers instead.
pub fn f() -> u8 {
    1
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP_PROJ"'/src/ok.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP_PROJ" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Forbidden unsafe code"
}

# Regression: a multi-line /* ... */ block comment containing `unsafe {` must
# be stripped (block-comment state machine), not just single-line comments.
@test "rust-quality: unsafe inside a multi-line block comment is NOT flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/ok.rs <<'EOF'
/*
legacy implementation:
unsafe {
    do_thing();
}
*/
pub fn f() -> u8 {
    1
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP_PROJ"'/src/ok.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP_PROJ" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Forbidden unsafe code"
}
