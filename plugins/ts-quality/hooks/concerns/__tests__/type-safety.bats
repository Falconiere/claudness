#!/usr/bin/env bats
# Concern: type-safety — 15-type-as (forbidden `as` assertions, with the
# export-re-export and primitive-cast carve-outs) and 50-type-dup (duplicate
# exported type across packages). 45-typeguard and 40-factory have no dedicated
# @test in the deleted monolith suite, so this file covers the `as` + type-dup
# rules that did. Ported VERBATIM; only change: drive the ASSEMBLED module.

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

@test "ts-quality: as null / as void primitive casts are flagged" {
  _ts_project
  cat > src/a.ts <<'EOF'
const a = something as null;
const b = other as void;
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Forbidden 'as' type assertion"
}

@test "ts-quality: duplicate exported type across packages is flagged (git grep)" {
  _ts_project
  mkdir -p packages/a/src packages/b/src
  printf 'export interface Widget { id: string }\n' > packages/a/src/widget.ts
  git add packages/a/src/widget.ts
  git -c user.email=t@t -c user.name=t commit -q -m widget
  printf 'export interface Widget { id: string }\n' > packages/b/src/widget2.ts
  payload='{"tool_input":{"file_path":"'"$TMP"'/packages/b/src/widget2.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "already defined in packages/a/src/widget.ts"
}
