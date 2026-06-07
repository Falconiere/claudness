#!/usr/bin/env bats
# Tests for hooks/post-tools/modules/ts-quality.sh

HOOK="${BATS_TEST_DIRNAME}/../ts-quality.sh"

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
