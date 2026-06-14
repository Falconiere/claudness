#!/usr/bin/env bats
# Concern: size — 25-size-file (maxFileLines; comments/blanks excluded; eslint
# config crediting) and 30-size-fn (maxFnLines across arrows, function exprs,
# class methods, multi-line params, template-literal braces, defaulted generics).
# Ported VERBATIM from the deleted monolith per-rule suite; the only change is
# they drive the ASSEMBLED registry module (assembled in setup).

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

# Regression: a brace-less single-line arrow (`const x = () => expr;`) set
# infn=1 but never released it (no `{`, no `;` fallback), so the NEXT function
# was misattributed to the arrow's start line and falsely flagged "too long".
@test "ts-quality: one-line arrow consts before a function do not cause a false positive" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFnLines":5}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/a.ts <<'EOF'
export const noop = () => undefined;
export const square = (x: number) => x * x;
export const upper = (s: string) => s.trim();
export function foo(): number {
  const a = 1;
  const b = 2;
  return a + b;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Function too long"
}

# Guard the inverse: a genuinely long function after one-line arrows is still
# flagged (the release must not suppress real detection).
@test "ts-quality: long function after one-line arrows is still flagged" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFnLines":3}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/a.ts <<'EOF'
export const noop = () => undefined;
export function foo(): number {
  const a = 1;
  const b = 2;
  const c = 3;
  const d = 4;
  return a + b + c + d;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Function too long"
}

# Regression: the old detector keyed the fn end on a column-0 `}` and only
# recognised top-level `function`/`const = (` forms, so a long method inside a
# class was never measured. The brace-depth counter measures each method to its
# own (indented) close.
@test "ts-quality: long method inside a class IS flagged" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFnLines":3}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/svc.ts <<'EOF'
export class Service {
  process(x: number): number {
    const a = x + 1;
    const b = a + 1;
    const c = b + 1;
    const d = c + 1;
    return d;
  }
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/svc.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Function too long"
}

# Regression: a short method followed by other class members must be measured to
# ITS OWN close, not the class close — the brace-depth counter resets per method.
@test "ts-quality: short class method followed by other members is NOT flagged" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFnLines":3}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/svc.ts <<'EOF'
export class Service {
  ping(): number {
    return 1;
  }
  a = 1;
  b = 2;
  c = 3;
  d = 4;
  e = 5;
  f = 6;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/svc.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Function too long"
}

# Regression: an arrow with a multi-line parameter list is measured from the
# `const NAME = (` line through the brace-balanced close.
@test "ts-quality: arrow const with a multi-line param list IS flagged" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFnLines":3}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/a.ts <<'EOF'
export const compute = (
  a: number,
  b: number,
  c: number,
) => {
  const sum = a + b + c;
  return sum * 2;
};
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Function too long"
}

# Regression: a column-0 `}` inside a (brace-balanced) multi-line template
# literal must not end the measured range early. The old `^}` marker cut the
# function at the template's close brace and under-counted a genuinely long fn.
@test "ts-quality: column-0 } inside a template literal does not end the fn early (regression)" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFnLines":5}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/tmpl.ts <<'EOF'
export function render(): string {
  const css = `
.foo {
  color: red;
}
`;
  const a = 1;
  const b = 2;
  const c = 3;
  return css + a + b + c;
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/tmpl.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Function too long"
}

# Regression: a `const NAME = function() {` expression (no space before the
# paren) must be detected, not just the `= (` arrow form.
@test "ts-quality: long const function-expression is flagged" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFnLines":3}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/a.ts <<'EOF'
export const fn = function() {
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

# Regression: a method with a defaulted generic param (`<T = U>`) must still be
# measured — the `=` inside the type args must not break start detection.
@test "ts-quality: long class method with a defaulted generic is flagged" {
  _ts_project
  mkdir -p "$TMP/.claude"
  echo '{"lang":{"ts":{"maxFnLines":3}}}' > "$TMP/.claude/claudness.config.json"
  cat > src/svc.ts <<'EOF'
export class Service {
  process<T = number>(x: T): T {
    const a = x;
    const b = a;
    const c = b;
    const d = c;
    return d;
  }
}
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/svc.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Function too long"
}
