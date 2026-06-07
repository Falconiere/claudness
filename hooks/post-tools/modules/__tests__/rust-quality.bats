#!/usr/bin/env bats
# Tests for hooks/post-tools/modules/rust-quality.sh

HOOK="${BATS_TEST_DIRNAME}/../rust-quality.sh"

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
