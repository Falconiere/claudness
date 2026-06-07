#!/usr/bin/env bats
# Tests for hooks/pre-tools/modules/protected-files.sh

HOOK="${BATS_TEST_DIRNAME}/../protected-files.sh"

setup() {
  TMP=$(mktemp -d)
  export MY_CLAUDE_SETTINGS_DIR="$TMP/settings"
  mkdir -p "$MY_CLAUDE_SETTINGS_DIR"
  cat > "$MY_CLAUDE_SETTINGS_DIR/protected-files.txt" <<'TXT'
.env
.env.*
**/secrets/**
hooks/lib/**
hooks/**/*.sh
TXT
}

teardown() {
  unset MY_CLAUDE_SETTINGS_DIR
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

run_hook() {
  local file="$1"
  local payload
  payload=$(jq -n --arg p "$file" '{tool_name:"Edit",tool_input:{file_path:$p}}')
  tool_name=Edit input="$payload" run bash "$HOOK" <<<"$payload"
}

@test "protected-files: blocks .env (bare basename)" {
  run_hook ".env"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "protected-files: blocks hooks/lib/detect.sh (path glob)" {
  run_hook "hooks/lib/detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "protected-files: allows src/foo.ts" {
  run_hook "src/foo.ts"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Regression: Claude's Edit/Write sends absolute paths. Without prefix
# normalization, [[ /abs/path == hooks/lib/** ]] is false and trusted-script
# protection silently no-ops.
@test "protected-files: blocks ABSOLUTE path under hooks/lib/** (real-world payload)" {
  REPO=$(cd "$(mktemp -d)" && pwd -P)
  ( cd "$REPO" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init )
  mkdir -p "$REPO/hooks/lib"
  touch "$REPO/hooks/lib/detect.sh"
  ( cd "$REPO" && run_hook "$REPO/hooks/lib/detect.sh" >/dev/null 2>&1 )
  # Re-run inside the repo so detect_project_root resolves correctly.
  cd "$REPO"
  run_hook "$REPO/hooks/lib/detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$REPO"
}

@test "protected-files: blocks ABSOLUTE path under hooks/**/*.sh" {
  REPO=$(cd "$(mktemp -d)" && pwd -P)
  ( cd "$REPO" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init )
  mkdir -p "$REPO/hooks/post-tools/modules"
  touch "$REPO/hooks/post-tools/modules/rust-quality.sh"
  cd "$REPO"
  run_hook "$REPO/hooks/post-tools/modules/rust-quality.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$REPO"
}

@test "protected-files: allows ABSOLUTE path outside protected globs" {
  REPO=$(cd "$(mktemp -d)" && pwd -P)
  ( cd "$REPO" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init )
  mkdir -p "$REPO/src"
  touch "$REPO/src/foo.ts"
  cd "$REPO"
  run_hook "$REPO/src/foo.ts"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$REPO"
}
