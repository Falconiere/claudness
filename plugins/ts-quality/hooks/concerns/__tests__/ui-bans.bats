#!/usr/bin/env bats
# Concern: ui-bans — 72-ui-radix (raw @radix-ui import banned; comment-only
# import carve-out) and 70-ui-confirm (confirm()/alert()). The deleted monolith
# suite only exercised the radix rule directly; those tests are ported here.
# Ported VERBATIM; only change: drive the ASSEMBLED registry module.

TOOLU_LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../toolu/hooks/lib" && pwd)"
export TOOLU_LIB_DIR

setup() {
  TMP=$(mktemp -d)
  export CLAUDE_CONFIG_DIR="$TMP/cfg"
  REGISTER="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/register.sh"
  bash "$REGISTER" </dev/null
  HOOK="$CLAUDE_CONFIG_DIR/toolu/post-tools.d/ts-quality@toolu__ts-quality.sh"

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

@test "ts-quality: raw radix import is flagged" {
  _ts_project
  cat > src/a.ts <<'EOF'
import { Dialog } from "@radix-ui/react-dialog";
export const x = 1;
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Raw radix import"
}

# Regression: the rule used a raw grep, so a radix import on a `//` comment line
# false-positived. Comment lines are now filtered first.
@test "ts-quality: radix import only in a comment is NOT flagged" {
  _ts_project
  cat > src/a.ts <<'EOF'
// import { Dialog } from "@radix-ui/react-dialog";
export const x = 1;
EOF
  payload='{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}'
  tool_name=Write input="$payload" PROJECT_ROOT="$TMP" run bash "$HOOK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Raw radix import"
}
