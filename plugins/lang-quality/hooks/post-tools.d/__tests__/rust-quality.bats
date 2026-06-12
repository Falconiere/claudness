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
  echo "$output" | grep -q "Forbidden lint suppression"
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
  echo "$output" | grep -q "Forbidden lint suppression"
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

@test "rust-quality: cfg_attr(allow) lint suppression is flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/bad.rs <<'EOF'
#[cfg_attr(test, allow(dead_code))]
fn helper() {}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Forbidden lint suppression"
}

@test "rust-quality: unreachable! in src/ is flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _rust_project
  cat > src/bad.rs <<'EOF'
fn f(x: u8) -> u8 {
    match x {
        0 => 1,
        _ => unreachable!("never"),
    }
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "unreachable!"
}

@test "rust-quality: bare #[rstest] test attribute outside tests/ is flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/foo.rs <<'EOF'
#[rstest]
fn it_works() {
    assert_eq!(1, 1);
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/foo.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Rust test file outside tests/"
}

@test "rust-quality: #[allow] mentioned in a line comment is NOT flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/ok.rs <<'EOF'
// historically this used #[allow(dead_code)] elsewhere; removed now.
fn helper() -> u8 {
    1
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/ok.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Forbidden lint suppression"
}

@test "rust-quality: canonical inline #[cfg(test)] mod produces one violation, not two" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/lib.rs <<'EOF'
pub fn add(a: u8, b: u8) -> u8 {
    a + b
}

#[cfg(test)]
mod tests {
    #[test]
    fn it_adds() {
        assert_eq!(super::add(1, 2), 3);
    }
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/lib.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Inline #\[cfg(test)\]"
  ! echo "$output" | grep -q "Rust test file outside tests/"
}

@test "rust-quality: pub(crate) const fn is subject to the fn-length limit" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"rust":{"maxFnLines":3}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/m.rs <<'EOF'
pub(crate) const fn big() -> u8 {
    let a = 1;
    let b = 2;
    let c = 3;
    a + b + c
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/m.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Function too long"
}

# Regression: the fn-end marker used /^[[:space:]]*\}/, so the close of the
# FIRST inner if/else/match block ended the measured range — any long fn with
# control flow was measured as a few lines and never flagged.
@test "rust-quality: long fn with inner if/else is measured to its real close (regression)" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"rust":{"maxFnLines":5}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/long.rs <<'EOF'
fn long_with_branches(x: u8) -> u8 {
    let mut acc = 0;
    if x > 0 {
        acc += 1;
    } else {
        acc += 2;
    }
    acc += 3;
    acc += 4;
    acc
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/long.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Function too long"
}

# Regression: with the col-0 fn-end marker, the LAST method in an impl was
# measured to the impl's close — trailing non-fn items inflated its length and
# the report named the wrong fn. The brace-depth counter measures each method
# to its own close.
@test "rust-quality: short impl method followed by other items is NOT flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"rust":{"maxFnLines":5}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/m.rs <<'EOF'
pub struct Foo;
impl Foo {
    fn short(&self) -> u8 {
        1
    }
    const A: u8 = 1;
    const B: u8 = 2;
    const C: u8 = 3;
    const D: u8 = 4;
    const E: u8 = 5;
    const F: u8 = 6;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/m.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Function too long"
}

@test "rust-quality: long method inside an impl IS flagged" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"rust":{"maxFnLines":5}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/m.rs <<'EOF'
pub struct Foo;
impl Foo {
    fn long_method(&self, x: u8) -> u8 {
        let mut acc = 0;
        if x > 0 {
            acc += 1;
        } else {
            acc += 2;
        }
        acc += 3;
        acc
    }
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/m.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Function too long"
}

@test "rust-quality: #[bench] and #[wasm_bindgen_test] do not trigger tests/ placement" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  mkdir -p benches
  cat > benches/speed.rs <<'EOF'
#[bench]
fn bench_it(b: &mut Bencher) {
    b.iter(|| 1 + 1);
}
EOF
  cat > src/wasm_checks.rs <<'EOF'
#[wasm_bindgen_test]
fn browser_works() {
    assert_eq!(1, 1);
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/benches/speed.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "test file outside"
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/wasm_checks.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "test file outside"
}

@test "rust-quality: clearing one file does not clobber another file's failure" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  printf '#[allow(dead_code)]\nfn a() {}\n' > src/a.rs
  printf '#[allow(dead_code)]\nfn b() {}\n' > src/b.rs
  payload_a='{"tool_input":{"file_path":"'"$TMP"'/src/a.rs"}}'
  payload_b='{"tool_input":{"file_path":"'"$TMP"'/src/b.rs"}}'
  GATE="$TMP/.claude/tmp/quality-gate-status.json"

  tool_name=Edit input="$payload_a" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  tool_name=Edit input="$payload_b" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "failing"' "$GATE"

  # b.rs goes clean — a.rs's violation must survive and keep the gate failing.
  printf 'fn b() {}\n' > src/b.rs
  tool_name=Edit input="$payload_b" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "failing"' "$GATE"
  jq -e --arg f "$TMP/src/a.rs" '.entries[$f]' "$GATE"

  # a.rs goes clean too — now the gate may pass.
  printf 'fn a() {}\n' > src/a.rs
  tool_name=Edit input="$payload_a" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "passing"' "$GATE"
}

@test "rust-quality: failing gate owned by another hook survives a rust fail->clear cycle" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  mkdir -p "$TMP/.claude/tmp"
  GATE="$TMP/.claude/tmp/quality-gate-status.json"
  jq -n '{status: "failing", reason: "TS violation", source: "ts-quality-hook",
          file: "/p/x.ts", violations: "bad ts\n", updatedAt: "2026-01-01T00:00:00Z"}' > "$GATE"

  printf '#[allow(dead_code)]\nfn a() {}\n' > src/a.rs
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.rs"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "failing"' "$GATE"
  jq -e '.source == "rust-quality-hook"' "$GATE"

  # Rust file goes clean — the TS failure must be promoted back, not erased.
  printf 'fn a() {}\n' > src/a.rs
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  jq -e '.status == "failing"' "$GATE"
  jq -e '.source == "ts-quality-hook"' "$GATE"
  jq -e '.reason == "TS violation"' "$GATE"
}

@test "rust-quality: #[cfg(test)] only in a doc comment does NOT suppress placement enforcement" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  cat > src/foo.rs <<'EOF'
/// Example usage: annotate with #[cfg(test)] in your own crate.
#[tokio::test]
async fn it_works() {
    assert_eq!(1, 1);
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/foo.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  # The doc-comment mention must not trip the inline-cfg(test) rule...
  ! echo "$output" | grep -q "Inline #\[cfg(test)\]"
  # ...and placement enforcement must still fire on the real #[tokio::test].
  echo "$output" | grep -q "Rust test file outside tests/"
}

@test "rust-quality: over-limit message flags approximate size on unterminated /*" {
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  _rust_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"rust":{"maxFileLines":2}}}' > "$TMP/.claude/claudness.config.json"
  # A string containing /* flips count_code_lines into the raw-count fallback;
  # has_unterminated_block detects the unbalanced /* and the message says so.
  printf '%s\n' 'let s = "/*";' 'let a = 1;' 'let b = 2;' 'let c = 3;' > src/m.rs
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/m.rs"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "exceeds 2-line limit"
  echo "$output" | grep -q "size approximated"
}
