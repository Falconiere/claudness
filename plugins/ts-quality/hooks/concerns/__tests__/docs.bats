#!/usr/bin/env bats
# Concern: docs — 92-docs (missing-JSDoc advisory on exported API, pragma carve-out,
# verbose-JSDoc nag). The 94-handler fragment's await-advisory tests live in
# error-handling.bats (error semantics); this file covers the JSDoc rules.
# Ported VERBATIM from the deleted monolith per-rule suite; only change: drive the
# ASSEMBLED registry module.

TOOLU_LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../toolu/hooks/lib" && pwd)"
export TOOLU_LIB_DIR

setup() {
  TMP=$(mktemp -d)
  export CLAUDE_CONFIG_DIR="$TMP/cfg"
  REGISTER="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/register.sh"
  bash "$REGISTER" </dev/null
  HOOK="$CLAUDE_CONFIG_DIR/toolu/post-tools.d/ts-quality@falconiere__ts-quality.sh"

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

# Regression: the verbose-JSDoc awk reset its counter when `/**` appeared in
# prose inside a block, so a long block with that substring escaped the nag.
@test "ts-quality: verbose JSDoc with /** in prose mid-block is still flagged" {
  _ts_project
  cat > src/api.ts <<'EOF'
/**
 * Does the thing.
 * line 3
 * line 4
 * use a /** block for docs, they said
 * line 6
 * line 7
 * line 8
 * line 9
 * line 10
 * line 11
 * line 12
 * line 13
 */
export function doThing() {
  return 1;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/api.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "JSDoc block is"
}

@test "ts-quality: exported function without JSDoc emits a non-blocking docs advisory" {
  _ts_project
  cat > src/api.ts <<'EOF'
export function doThing() {
  return 1;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/api.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "missing a JSDoc"
  ! echo "$output" | grep -q "QUALITY VIOLATION"
}

@test "ts-quality: docs advisory respects a pragma between JSDoc and export" {
  _ts_project
  cat > src/api.ts <<'EOF'
/** Does the thing. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function doThing() {
  return 1;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/api.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "missing a JSDoc"
}

@test "ts-quality: documented export produces no docs advisory" {
  _ts_project
  cat > src/api.ts <<'EOF'
/** Does the thing. */
export function doThing() {
  return 1;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/api.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "missing a JSDoc"
}

@test "ts-quality: camelCase exported arrow API without JSDoc gets a docs advisory" {
  _ts_project
  cat > src/a.ts <<'EOF'
export const myApi = () => {
  return 1;
};
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "missing a JSDoc"
}
