#!/usr/bin/env bats
# Concern: suppression — 65-suppression (eslint-disable / @ts-expect-error /
# @ts-ignore forbidden in src/, with the test-file carve-out for @ts-expect-error).
# Ported VERBATIM from the deleted monolith per-rule suite; only change: drive
# the ASSEMBLED registry module.

CLAUDNESS_LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../claudness/hooks/lib" && pwd)"
export CLAUDNESS_LIB_DIR

setup() {
  TMP=$(mktemp -d)
  export CLAUDE_CONFIG_DIR="$TMP/cfg"
  REGISTER="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/register.sh"
  bash "$REGISTER" </dev/null
  HOOK="$CLAUDE_CONFIG_DIR/claudness/post-tools.d/ts-quality@falconiere__ts-quality.sh"

  TMP_PROJ="$TMP/proj"
  mkdir -p "$TMP_PROJ"
  cd "$TMP_PROJ"
  TMP="$TMP_PROJ"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ -d "$CLAUDE_CONFIG_DIR" ] && rm -rf "$CLAUDE_CONFIG_DIR"
}

_ts_project() {
  echo '{}' > tsconfig.json
  echo '{"name":"x"}' > package.json
  touch bun.lock
  mkdir -p src
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m setup
}

@test "ts-quality: eslint-disable comment is flagged as suppression" {
  _ts_project
  cat > src/bad.ts <<'EOF'
// eslint-disable-next-line
export const a = thing();
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Forbidden suppression comment"
}

@test "ts-quality: @ts-expect-error is flagged outside test files" {
  _ts_project
  cat > src/bad.ts <<'EOF'
// @ts-expect-error legacy boundary
export const b = thing();
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Forbidden suppression comment"
}

@test "ts-quality: @ts-expect-error is allowed in test files" {
  _ts_project
  echo 'export const code = 1;' > src/code.ts
  mkdir -p src/__tests__
  cat > src/__tests__/code.test.ts <<'EOF'
// @ts-expect-error asserting a type error is the point of this test
const z: string = 123;
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/__tests__/code.test.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Forbidden suppression comment"
}

@test "ts-quality: @ts-ignore inside a /** */ block comment is flagged" {
  _ts_project
  cat > src/bad.ts <<'EOF'
/** @ts-ignore */
export const a = thing();
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Forbidden suppression comment"
}
