#!/usr/bin/env bats
# register.sh syncs this plugin's pre-tools.d modules into the claudness
# runtime registry as <spec>__<name>.sh, prunes its own stale entries, and
# never touches other plugins' files.

setup() {
  TMP=$(mktemp -d)
  export CLAUDE_CONFIG_DIR="$TMP/cfg"
  REGISTER="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/register.sh"
  SRC_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../pre-tools.d" && pwd)"
}

teardown() { rm -rf "$TMP"; }

@test "register: syncs every module into pre-tools.d with the spec prefix" {
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  for src in "$SRC_DIR"/*.sh; do
    name=$(basename "$src")
    dst="$CLAUDE_CONFIG_DIR/claudness/pre-tools.d/ast-grep@falconiere__${name}"
    [ -f "$dst" ]
    cmp -s "$src" "$dst"
  done
}

@test "register: prunes its own stale entries but not other plugins'" {
  regdir="$CLAUDE_CONFIG_DIR/claudness/pre-tools.d"
  mkdir -p "$regdir"
  echo '#!/usr/bin/env bash' > "$regdir/ast-grep@falconiere__removed-module.sh"
  echo '#!/usr/bin/env bash' > "$regdir/other@market__keep.sh"
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  [ ! -f "$regdir/ast-grep@falconiere__removed-module.sh" ]
  [ -f "$regdir/other@market__keep.sh" ]
}

@test "register: prunes legacy code-intel@falconiere residue from the former bundled plugin" {
  regdir="$CLAUDE_CONFIG_DIR/claudness/pre-tools.d"
  mkdir -p "$regdir"
  echo '#!/usr/bin/env bash' > "$regdir/code-intel@falconiere__search-nudge.sh"
  echo '#!/usr/bin/env bash' > "$regdir/code-intel@falconiere__comemory-scope.sh"
  echo '#!/usr/bin/env bash' > "$regdir/other@market__keep.sh"
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  [ ! -f "$regdir/code-intel@falconiere__search-nudge.sh" ]
  [ ! -f "$regdir/code-intel@falconiere__comemory-scope.sh" ]
  [ -f "$regdir/other@market__keep.sh" ]
}

@test "register: refreshes a registry copy that drifted from source" {
  regdir="$CLAUDE_CONFIG_DIR/claudness/pre-tools.d"
  mkdir -p "$regdir"
  echo 'stale content' > "$regdir/ast-grep@falconiere__search-nudge.sh"
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  cmp -s "$SRC_DIR/search-nudge.sh" "$regdir/ast-grep@falconiere__search-nudge.sh"
}

@test "register: idempotent (second run changes nothing, exits 0)" {
  bash "$REGISTER" <<<'{}'
  before=$(ls "$CLAUDE_CONFIG_DIR/claudness/pre-tools.d" | sort)
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  after=$(ls "$CLAUDE_CONFIG_DIR/claudness/pre-tools.d" | sort)
  [ "$before" = "$after" ]
}

@test "register: writes are atomic (no *.tmp.* leftovers)" {
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  found=$(find "$CLAUDE_CONFIG_DIR/claudness" -name '*.tmp.*' | wc -l | tr -d ' ')
  [ "$found" = "0" ]
}

@test "register: emits nothing on stdout (SessionStart hygiene)" {
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "register e2e: synced modules execute through the core dispatcher when installed" {
  CORE_MOD="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../claudness/hooks/pre-tools" && pwd)/mod.sh"
  bash "$REGISTER" <<<'{}'
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
  printf '%s' '{"plugins":{"ast-grep@falconiere":{}}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run env -u CLAUDE_PLUGINS_REGISTRY CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" HOME="$TMP" \
    bash "$CORE_MOD" <<<'{"tool_name":"Grep","tool_input":{"pattern":"fn handle_request","glob":"*.rs"}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("ast-grep")' >/dev/null
}

@test "register e2e: synced modules are gated off when the plugin is definitively absent" {
  CORE_MOD="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../claudness/hooks/pre-tools" && pwd)/mod.sh"
  bash "$REGISTER" <<<'{}'
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
  printf '%s' '{"plugins":{}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run env -u CLAUDE_PLUGINS_REGISTRY CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" HOME="$TMP" \
    bash "$CORE_MOD" <<<'{"tool_name":"Grep","tool_input":{"pattern":"fn handle_request","glob":"*.rs"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "register: clears its own AGED orphaned tmp residue, keeps fresh + foreign tmp" {
  regdir="$CLAUDE_CONFIG_DIR/claudness/pre-tools.d"
  mkdir -p "$regdir"
  # Aged orphan (ours): from a crashed run — must be removed.
  echo 'partial' > "$regdir/ast-grep@falconiere__search-nudge.sh.tmp.12345"
  touch -t 202601010000 "$regdir/ast-grep@falconiere__search-nudge.sh.tmp.12345"
  # Fresh tmp (ours): a concurrent SessionStart mid-write — must survive.
  echo 'partial' > "$regdir/ast-grep@falconiere__fresh-module.sh.tmp.777"
  # Foreign tmp: never ours to touch, fresh or aged.
  echo 'partial' > "$regdir/other@market__keep.sh.tmp.99"
  touch -t 202601010000 "$regdir/other@market__keep.sh.tmp.99"
  run bash "$REGISTER" <<<'{}'
  [ "$status" -eq 0 ]
  [ ! -f "$regdir/ast-grep@falconiere__search-nudge.sh.tmp.12345" ]
  [ -f "$regdir/ast-grep@falconiere__fresh-module.sh.tmp.777" ]
  [ -f "$regdir/other@market__keep.sh.tmp.99" ]
}
