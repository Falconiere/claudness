#!/usr/bin/env bats
# register.sh mirrors this plugin's post-tools.d modules into the claudness
# runtime registry as <spec>__<name>.sh, prunes its own stale + tmp residue,
# and never touches other plugins' files.

setup() {
  TMP=$(mktemp -d)
  export CLAUDE_CONFIG_DIR="$TMP/cfg"
  REGISTER="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/register.sh"
  SRC_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../post-tools.d" && pwd)"
}
teardown() { rm -rf "$TMP"; }

@test "register: syncs every module into post-tools.d with the spec prefix" {
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  for src in "$SRC_DIR"/*.sh; do
    name=$(basename "$src")
    [ -f "$CLAUDE_CONFIG_DIR/claudness/post-tools.d/lang-quality@falconiere__${name}" ]
    cmp -s "$src" "$CLAUDE_CONFIG_DIR/claudness/post-tools.d/lang-quality@falconiere__${name}"
  done
}

@test "register: prunes its own stale entries but not other plugins'" {
  d="$CLAUDE_CONFIG_DIR/claudness/post-tools.d"; mkdir -p "$d"
  echo x > "$d/lang-quality@falconiere__gone.sh"
  echo x > "$d/other@market__keep.sh"
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  [ ! -f "$d/lang-quality@falconiere__gone.sh" ]
  [ -f "$d/other@market__keep.sh" ]
}

@test "register: clears its own AGED tmp residue, keeps fresh + foreign" {
  d="$CLAUDE_CONFIG_DIR/claudness/post-tools.d"; mkdir -p "$d"
  echo x > "$d/lang-quality@falconiere__rust-quality.sh.tmp.111"
  touch -t 202601010000 "$d/lang-quality@falconiere__rust-quality.sh.tmp.111"
  echo x > "$d/lang-quality@falconiere__ts-quality.sh.tmp.222"
  echo x > "$d/other@market__keep.sh.tmp.9"; touch -t 202601010000 "$d/other@market__keep.sh.tmp.9"
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  [ ! -f "$d/lang-quality@falconiere__rust-quality.sh.tmp.111" ]
  [ -f "$d/lang-quality@falconiere__ts-quality.sh.tmp.222" ]
  [ -f "$d/other@market__keep.sh.tmp.9" ]
}

@test "register: idempotent + silent on stdout" {
  bash "$REGISTER" <<<'{}'
  before=$(ls "$CLAUDE_CONFIG_DIR/claudness/post-tools.d" | sort)
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$before" = "$(ls "$CLAUDE_CONFIG_DIR/claudness/post-tools.d" | sort)" ]
}

# End-to-end: register -> registry -> core PostToolUse dispatcher. Uses
# ts-quality's numeric-throw rule (no cargo/ast-grep dependency) for a
# deterministic signal. cwd must be the project so mod.sh's PROJECT_ROOT
# (git rev-parse) resolves there.
_ts_project() {
  proj="$TMP/ts"; mkdir -p "$proj/src"
  ( cd "$proj" && git init -q && echo '{}' > tsconfig.json && echo '{"name":"x"}' > package.json \
    && touch bun.lock && printf 'export function b(){ throw 42; }\n' > src/bad.ts \
    && git add -A && git -c user.email=t@t -c user.name=t commit -q -m s )
  CORE_MOD="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../claudness/hooks/post-tools" && pwd)/mod.sh"
}

@test "register e2e: a synced module fires through the core dispatcher when installed" {
  _ts_project
  bash "$REGISTER" <<<'{}'
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
  printf '%s' '{"plugins":{"lang-quality@falconiere":{}}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash -c 'cd "'"$proj"'" && env -u CLAUDE_PLUGINS_REGISTRY CLAUDE_CONFIG_DIR="'"$CLAUDE_CONFIG_DIR"'" HOME="'"$TMP"'" bash "'"$CORE_MOD"'" <<<'"'"'{"tool_name":"Edit","tool_input":{"file_path":"'"$proj"'/src/bad.ts"},"tool_response":{}}'"'"''
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "non-Error literal"
}

@test "register e2e: synced modules are gated off when the plugin is absent" {
  _ts_project
  bash "$REGISTER" <<<'{}'
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
  printf '%s' '{"plugins":{}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run bash -c 'cd "'"$proj"'" && env -u CLAUDE_PLUGINS_REGISTRY CLAUDE_CONFIG_DIR="'"$CLAUDE_CONFIG_DIR"'" HOME="'"$TMP"'" bash "'"$CORE_MOD"'" <<<'"'"'{"tool_name":"Edit","tool_input":{"file_path":"'"$proj"'/src/bad.ts"},"tool_response":{}}'"'"''
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "non-Error literal"
}
