#!/usr/bin/env bats
# Concern: gating — 00-preamble / 99-finalize entry and exit guards: no-op
# outside a TS project, no-op when no package manager is detected, and fail-soft
# (silent exit 0) when CLAUDNESS_LIB_DIR is unset. Ported VERBATIM from the
# deleted monolith per-rule suite; only change: drive the ASSEMBLED registry
# module.

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

@test "ts-quality: exits 0 silently when CLAUDNESS_LIB_DIR is unset (fail soft)" {
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/index.ts"}}'
  run env -u CLAUDNESS_LIB_DIR tool_name=Write input="$payload" PROJECT_ROOT="$TMP" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
