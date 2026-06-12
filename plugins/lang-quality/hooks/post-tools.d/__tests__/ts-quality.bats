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

@test "ts-quality: project config lowers maxFileLines, flags a file the default would not" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFileLines":10}}}' > "$TMP/.claude/claudness.config.json"
  : > src/big.ts
  for i in $(seq 1 15); do echo "export const v$i = $i;" >> src/big.ts; done
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/big.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "exceeds 10-line limit"
}

@test "ts-quality: comments and blank lines do not count toward maxFileLines" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFileLines":10}}}' > "$TMP/.claude/claudness.config.json"
  # 8 code lines, padded with comments + blanks past the raw-line limit of 10.
  : > src/padded.ts
  for i in $(seq 1 8); do
    echo "// explanatory comment $i" >> src/padded.ts
    echo "" >> src/padded.ts
    echo "export const v$i = $i;" >> src/padded.ts
  done
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/padded.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "exceeds 10-line limit"
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

@test "ts-quality: over-limit message credits eslint when its JSON config sets the limit" {
  _ts_project
  echo '{"rules":{"max-lines":10}}' > .eslintrc.json
  git add .eslintrc.json; git -c user.email=t@t -c user.name=t commit -q -m eslint
  : > src/big.ts
  for i in $(seq 1 15); do echo "export const v$i = $i;" >> src/big.ts; done
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/big.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "eslint enforces this max-lines limit"
}

@test "ts-quality: over-limit message flags a non-machine-readable linter config (.eslintrc.cjs)" {
  _ts_project
  echo 'module.exports = { rules: {} };' > .eslintrc.cjs
  git add .eslintrc.cjs; git -c user.email=t@t -c user.name=t commit -q -m eslint
  # No project override, no JSON config -> falls to the 300 default while a
  # linter is detected; message must say the limit didn't come from its config.
  : > src/huge.ts
  for i in $(seq 1 301); do echo "export const v$i = $i;" >> src/huge.ts; done
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/huge.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "didn't come from its config"
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

@test "ts-quality: catch that returns null is flagged as swallow" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  _ts_project
  cat > src/bad.ts <<'EOF'
export function f() {
  try {
    risky();
  } catch (e) {
    return null;
  }
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/bad.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "swallows the error"
}

@test "ts-quality: await with no try/catch emits a non-blocking advisory" {
  _ts_project
  cat > src/a.ts <<'EOF'
/** Fetch a thing. */
export async function f() {
  const r = await fetchThing("x");
  return r;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uses await with no try/catch"
  ! echo "$output" | grep -q "QUALITY VIOLATION"
}

@test "ts-quality: await inside try/catch produces no error-handling advisory" {
  _ts_project
  cat > src/a.ts <<'EOF'
/** Fetch a thing safely. */
export async function f() {
  try {
    return await fetchThing("x");
  } catch (e) {
    throw new Error("fetch failed", { cause: e });
  }
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "uses await with no try/catch"
}

@test "ts-quality: ast-grep crash is surfaced as a violation, not silent pass" {
  _ts_project
  # Stub ast-grep that crashes (exit > 1 with stderr noise).
  mkdir -p "$TMP/bin"
  printf '#!/bin/sh\necho boom >&2\nexit 2\n' > "$TMP/bin/ast-grep"
  chmod +x "$TMP/bin/ast-grep"
  cat > src/good.ts <<'EOF'
/** clean */
export function good() {
  return 1;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/good.ts"}}'
  PATH="$TMP/bin:$PATH" tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ast-grep failed"
  echo "$output" | grep -q "boom"
  echo "$output" | grep -q "exit 2"
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

@test "ts-quality: export { foo as Bar } re-export is not flagged as an as-assertion" {
  _ts_project
  cat > src/reexport.ts <<'EOF'
import { foo } from "@/foo";
export { foo as Bar };
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/reexport.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Forbidden 'as' type assertion"
}

@test "ts-quality: export const x = foo as Bar IS flagged (not exempted as an export)" {
  _ts_project
  cat > src/a.ts <<'EOF'
export const x = foo as Bar;
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Forbidden 'as' type assertion"
}

@test "ts-quality: long exported arrow const is subject to the fn-length limit" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFnLines":3}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/a.ts <<'EOF'
export const fn = () => {
  const a = 1;
  const b = 2;
  const c = 3;
  return a + b + c;
};
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Function too long"
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
