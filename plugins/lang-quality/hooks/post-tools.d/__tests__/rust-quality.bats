#!/usr/bin/env bats
# Tests for the lang-quality plugin's rust-quality.sh registry module.

HOOK="${BATS_TEST_DIRNAME}/../rust-quality.sh"

# Core lib lives in the sibling claudness plugin; the dispatcher provides this
# env var in production, the tests provide it here.
CLAUDNESS_LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../claudness/hooks/lib" && pwd)"
export CLAUDNESS_LIB_DIR

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "rust-quality: no-op outside a Rust project (no Cargo.toml)" {
  payload='{"tool_input":{"file_path":"/nonexistent.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Error-handling rule helpers ---

# Set up minimal Rust project so detect_rust passes.
_rust_project() {
  printf '[package]\nname = "x"\nversion = "0.1.0"\n' > Cargo.toml
  mkdir -p src
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m setup
}

@test "rust-quality: .unwrap() in src/ is flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _rust_project
  cat > src/bad.rs <<'EOF'
fn main() {
    let x = some_result().unwrap();
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q ".unwrap()"
}

@test "rust-quality: .expect() in src/ is flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _rust_project
  cat > src/bad.rs <<'EOF'
fn main() {
    let y = thing.expect("nope");
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q ".expect()"
}

@test "rust-quality: panic!/todo!/unimplemented! in src/ is flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _rust_project
  cat > src/bad.rs <<'EOF'
fn main() {
    panic!("explode");
    todo!();
    unimplemented!();
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "panic!/todo!/unimplemented!"
}

@test "rust-quality: clean Result-based code produces no error output" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/good.rs <<'EOF'
fn main() -> Result<(), std::io::Error> {
    let _ = std::fs::read_to_string("x")?;
    Ok(())
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/good.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "QUALITY VIOLATION"
}

@test "rust-quality: Edit tool extracts file path and flags violations (regression)" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/bad.rs <<'EOF'
#[allow(dead_code)]
fn helper() {}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.rs"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Forbidden #\[allow"
}

# Regression: the PostToolUse matcher includes MultiEdit, but the file-path
# extraction only ran for Write/Edit — a MultiEdit on a .rs file (with
# CLAUDE_FILE_PATHS unset) silently skipped all quality checks.
@test "rust-quality: MultiEdit extracts file path and flags violations (regression)" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/bad.rs <<'EOF'
#[allow(dead_code)]
fn helper() {}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.rs"}}'
  tool_name=MultiEdit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Forbidden #\[allow"
}

@test "rust-quality: gate is cleared when the failing file is re-edited clean" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/bad.rs <<'EOF'
#[allow(dead_code)]
fn helper() {}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.rs"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "failing"' "$TMP/.claude/tmp/quality-gate-status.json"

  cat > src/bad.rs <<'EOF'
fn helper() {}
EOF
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "passing"' "$TMP/.claude/tmp/quality-gate-status.json"
  jq -e '.source == "rust-quality-hook"' "$TMP/.claude/tmp/quality-gate-status.json"
}

@test "rust-quality: ast-grep crash is surfaced as a violation, not silent pass" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  # Stub ast-grep that crashes (exit > 1 with stderr noise).
  mkdir -p "$TMP/bin"
  printf '#!/bin/sh\necho boom >&2\nexit 2\n' > "$TMP/bin/ast-grep"
  chmod +x "$TMP/bin/ast-grep"
  cat > src/good.rs <<'EOF'
fn helper() {}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/good.rs"}}'
  PATH="$TMP/bin:$PATH" tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ast-grep failed"
  # The captured stderr detail must be surfaced so the agent sees WHAT broke.
  echo "$output" | grep -q "boom"
  echo "$output" | grep -q "exit 2"
}

@test "rust-quality: gate-status file is written on violation" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _rust_project
  cat > src/bad.rs <<'EOF'
fn main() { panic!(); }
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -f "$TMP/.claude/tmp/quality-gate-status.json" ]
  jq -e '.status == "failing"' "$TMP/.claude/tmp/quality-gate-status.json"
  jq -e '.source == "rust-quality-hook"' "$TMP/.claude/tmp/quality-gate-status.json"
}

@test "rust-quality: exits 0 silently when CLAUDNESS_LIB_DIR is unset (fail soft)" {
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/main.rs"}}'
  run env -u CLAUDNESS_LIB_DIR tool_name=Write input="$payload" PROJECT_ROOT="$TMP" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "rust-quality: test file (#[test]) outside tests/ is flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/foo.rs <<'EOF'
#[test]
fn it_works() {
    assert_eq!(1, 1);
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/foo.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Rust test file outside tests/"
}

@test "rust-quality: integration test under tests/ is accepted" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  mkdir -p tests
  cat > tests/integration_test.rs <<'EOF'
#[test]
fn it_works() {
    assert_eq!(1, 1);
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/tests/integration_test.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "test file outside"
}

@test "rust-quality: project config lowers maxFileLines, flags a file the default would not" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"rust":{"maxFileLines":10}}}' > "$TMP/.claude/claudness.config.json"
  : > src/big.rs
  for i in $(seq 1 15); do echo "pub const V$i: u32 = $i;" >> src/big.rs; done
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/big.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "exceeds 10-line limit"
}

@test "rust-quality: pub fn without /// doc emits a non-blocking docs advisory" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/api.rs <<'EOF'
pub fn do_thing() -> u32 {
    1
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/api.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "missing a /// doc"
  ! echo "$output" | grep -q "QUALITY VIOLATION"
}
