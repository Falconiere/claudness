#!/usr/bin/env bats
# register.sh ASSEMBLES concerns/[0-9][0-9]-*.sh into ONE registry module
# <spec>__ts-quality.sh under $CLAUDE_CONFIG_DIR/claudness/post-tools.d/,
# prunes its own stale entries + tmp residue, and never touches other plugins.

SPEC="ts-quality@falconiere"
MODULE="${SPEC}__ts-quality.sh"

setup() {
  TMP=$(mktemp -d)
  export CLAUDE_CONFIG_DIR="$TMP/cfg"
  REGISTER="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/register.sh"
  CONCERNS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../concerns" && pwd)"
  REG_DIR="$CLAUDE_CONFIG_DIR/claudness/post-tools.d"
}
teardown() { rm -rf "$TMP"; }

# Reproduce the assembly independently of register.sh: in-order concat of the
# numeric-prefixed fragments with a newline after each.
_expected_module() {
  local out="$1"; : > "$out"
  local f
  for f in "$CONCERNS_DIR"/[0-9][0-9]-*.sh; do
    cat "$f" >> "$out"
    printf '\n' >> "$out"
  done
}

# --- B.1: exactly ONE assembled file, not one-per-fragment ---
@test "register: produces exactly ONE module file for our spec prefix" {
  run bash "$REGISTER" </dev/null
  [ "$status" -eq 0 ]
  [ -f "$REG_DIR/$MODULE" ]
  count=$(find "$REG_DIR" -maxdepth 1 -name "${SPEC}__*.sh" | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

# --- B.2: assembled bytes == in-order concat of fragments ---
@test "register: module bytes equal the ordered concat of concerns/[0-9][0-9]-*.sh" {
  bash "$REGISTER" </dev/null
  _expected_module "$TMP/expected.sh"
  cmp "$TMP/expected.sh" "$REG_DIR/$MODULE"
}

# --- B.3: prune our own stale entry, keep foreign ---
@test "register: prunes its own stale <spec>__old-concern.sh, keeps other plugins'" {
  mkdir -p "$REG_DIR"
  echo stale > "$REG_DIR/${SPEC}__old-concern.sh"
  echo keep  > "$REG_DIR/other@market__keep.sh"
  run bash "$REGISTER" </dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$REG_DIR/${SPEC}__old-concern.sh" ]
  [ -f "$REG_DIR/other@market__keep.sh" ]
  count=$(find "$REG_DIR" -maxdepth 1 -name "${SPEC}__*.sh" | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
  [ -f "$REG_DIR/$MODULE" ]
}

# --- B.4: idempotency — same bytes, unchanged mtime on a second run ---
@test "register: idempotent — second run leaves the module byte- and mtime-stable, silent" {
  bash "$REGISTER" </dev/null
  before_sum=$(cksum < "$REG_DIR/$MODULE")
  before_mtime=$(stat -f %m "$REG_DIR/$MODULE")
  sleep 1
  run bash "$REGISTER" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  after_sum=$(cksum < "$REG_DIR/$MODULE")
  after_mtime=$(stat -f %m "$REG_DIR/$MODULE")
  [ "$before_sum" = "$after_sum" ]
  [ "$before_mtime" = "$after_mtime" ]
}

# --- B.5: aged tmp residue cleaned, fresh + foreign kept ---
@test "register: clears its own AGED tmp residue, keeps fresh + foreign tmp" {
  mkdir -p "$REG_DIR"
  echo x > "$REG_DIR/${SPEC}__ts-quality.sh.tmp.111"
  touch -t 202601010000 "$REG_DIR/${SPEC}__ts-quality.sh.tmp.111"
  echo x > "$REG_DIR/${SPEC}__ts-quality.sh.tmp.222"   # fresh — kept
  echo x > "$REG_DIR/other@market__keep.sh.tmp.9"; touch -t 202601010000 "$REG_DIR/other@market__keep.sh.tmp.9"
  run bash "$REGISTER" </dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$REG_DIR/${SPEC}__ts-quality.sh.tmp.111" ]
  [ -f "$REG_DIR/${SPEC}__ts-quality.sh.tmp.222" ]
  [ -f "$REG_DIR/other@market__keep.sh.tmp.9" ]
}

# End-to-end: register -> registry -> core PostToolUse dispatcher. Uses
# ts-quality's numeric-throw rule (no cargo/ast-grep dependency) for a
# deterministic signal. cwd must be the project so mod.sh's PROJECT_ROOT
# (git rev-parse) resolves there.
_ts_dispatch_project() {
  proj="$TMP/ts"; mkdir -p "$proj/src"
  ( cd "$proj" && git init -q && echo '{}' > tsconfig.json && echo '{"name":"x"}' > package.json \
    && touch bun.lock && printf 'export function b(){ throw 42; }\n' > src/bad.ts \
    && git add -A && git -c user.email=t@t -c user.name=t commit -q -m s )
  CORE_MOD="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../claudness/hooks/post-tools" && pwd)/mod.sh"
}

@test "register e2e: assembled module fires through the core dispatcher when installed" {
  _ts_dispatch_project
  bash "$REGISTER" </dev/null
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
  printf '%s' '{"plugins":{"ts-quality@falconiere":{}}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash -c 'cd "'"$proj"'" && env -u CLAUDE_PLUGINS_REGISTRY CLAUDE_CONFIG_DIR="'"$CLAUDE_CONFIG_DIR"'" HOME="'"$TMP"'" bash "'"$CORE_MOD"'" <<<'"'"'{"tool_name":"Edit","tool_input":{"file_path":"'"$proj"'/src/bad.ts"},"tool_response":{}}'"'"''
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "non-Error literal"
}

@test "register e2e: assembled module is gated off when the plugin is absent" {
  _ts_dispatch_project
  bash "$REGISTER" </dev/null
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
  printf '%s' '{"plugins":{}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash -c 'cd "'"$proj"'" && env -u CLAUDE_PLUGINS_REGISTRY CLAUDE_CONFIG_DIR="'"$CLAUDE_CONFIG_DIR"'" HOME="'"$TMP"'" bash "'"$CORE_MOD"'" <<<'"'"'{"tool_name":"Edit","tool_input":{"file_path":"'"$proj"'/src/bad.ts"},"tool_response":{}}'"'"''
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "non-Error literal"
}
