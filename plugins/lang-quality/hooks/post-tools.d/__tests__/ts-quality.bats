#!/usr/bin/env bats
# Tests for the lang-quality plugin's ts-quality.sh registry module.

HOOK="${BATS_TEST_DIRNAME}/../ts-quality.sh"

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

@test "ts-quality: no-op outside a TS project (no tsconfig)" {
  # No tsconfig committed → detect_ts returns "" → script exits 0 immediately.
  payload='{"tool_input":{"file_path":"/nonexistent.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ts-quality: no-op when TS project has no package manager detected" {
  # tsconfig present but no lockfile → detect_node_pm returns "" → exit 0.
  echo '{}' > tsconfig.json
  git add tsconfig.json
  git -c user.email=t@t -c user.name=t commit -q -m tsconfig
  payload='{"tool_input":{"file_path":"'"$TMP"'/foo.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Error-handling rule helpers ---

# Set up a minimal TS project (tsconfig + bun lockfile) so detect_ts/detect_node_pm pass.
_ts_project() {
  echo '{}' > tsconfig.json
  echo '{"name":"x"}' > package.json
  touch bun.lock
  mkdir -p src
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m setup
}

@test "ts-quality: empty catch block is flagged" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _ts_project
  cat > src/bad.ts <<'EOF'
export function bad() {
  try {
    foo();
  } catch (e) {}
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Empty catch block"
}

@test "ts-quality: silent .catch(() => {}) is flagged" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _ts_project
  cat > src/bad.ts <<'EOF'
export function bad() {
  foo().catch(() => {});
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Silent promise rejection"
}

@test "ts-quality: throw new Error() with no message is flagged" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _ts_project
  cat > src/bad.ts <<'EOF'
export function bad() {
  throw new Error();
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no message"
}

@test "ts-quality: throw of string literal is flagged" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _ts_project
  cat > src/bad.ts <<'EOF'
export function bad() {
  throw "bad";
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "string literal"
}

@test "ts-quality: throw of numeric literal is flagged" {
  _ts_project
  cat > src/bad.ts <<'EOF'
export function bad() {
  throw 42;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "non-Error literal"
}

@test "ts-quality: throw of null is flagged" {
  _ts_project
  cat > src/bad.ts <<'EOF'
export function bad() {
  throw null;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "non-Error literal"
}

# Regression: the PostToolUse matcher includes MultiEdit, but the file-path
# extraction only ran for Write/Edit — a MultiEdit on a .ts file (with
# CLAUDE_FILE_PATHS unset) silently skipped all quality checks.
@test "ts-quality: MultiEdit extracts file path and flags violations (regression)" {
  _ts_project
  cat > src/bad.ts <<'EOF'
export function bad() { throw 42; }
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=MultiEdit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "non-Error literal"
}

@test "ts-quality: clean error handling produces no error output" {
  _ts_project
  cat > src/good.ts <<'EOF'
export function good() {
  try {
    foo();
  } catch (e) {
    console.error(e);
    throw e;
  }
  foo().catch((err) => console.error(err));
  throw new Error("descriptive");
  throw new TypeError("typed");
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/good.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "QUALITY VIOLATION"
}

@test "ts-quality: throw literal inside // inline comment is NOT flagged" {
  _ts_project
  cat > src/good.ts <<'EOF'
export function good() {
  const x = 1; // we used to throw 5 here
  return x;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/good.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "non-Error literal"
}

@test "ts-quality: throw literal inside /* */ block comment is NOT flagged" {
  _ts_project
  cat > src/good.ts <<'EOF'
export function good() {
  /* avoid: throw 42 — use Error */
  return 1;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/good.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "non-Error literal"
}

@test "ts-quality: gate-status file is written on violation" {
  _ts_project
  cat > src/bad.ts <<'EOF'
export function bad() { throw 42; }
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Edit input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -f "$TMP/.claude/tmp/quality-gate-status.json" ]
  jq -e '.status == "failing"' "$TMP/.claude/tmp/quality-gate-status.json"
  jq -e '.source == "ts-quality-hook"' "$TMP/.claude/tmp/quality-gate-status.json"
}

@test "ts-quality: exits 0 silently when CLAUDNESS_LIB_DIR is unset (fail soft)" {
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/index.ts"}}'
  run env -u CLAUDNESS_LIB_DIR tool_name=Write input="$payload" PROJECT_ROOT="$TMP" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
