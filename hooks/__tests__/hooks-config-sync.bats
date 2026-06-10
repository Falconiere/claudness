#!/usr/bin/env bats
# Drift guard: settings/hooks.fragment.json and plugins/claudness/hooks/hooks.json
# must define the exact same hooks, differing only in the command path prefix
# (`${CLAUDE_PROJECT_DIR:-$HOME}/.claude/hooks/` vs `${CLAUDE_PLUGIN_ROOT}/scripts/`).
# If a hook is added/edited in one file but not the other, these tests fail.

FRAGMENT_PREFIX='${CLAUDE_PROJECT_DIR:-$HOME}/.claude/hooks/'
PLUGIN_PREFIX='${CLAUDE_PLUGIN_ROOT}/scripts/'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FRAGMENT="$REPO_ROOT/settings/hooks.fragment.json"
  PLUGIN="$REPO_ROOT/plugins/claudness/hooks/hooks.json"
}

# Strip the per-file command prefix, leaving the relative script path.
# ltrimstr is a no-op when the prefix is absent; the prefix tests below
# guarantee every command actually carries its expected prefix.
normalize() {
  jq -S --arg p1 "$FRAGMENT_PREFIX" --arg p2 "$PLUGIN_PREFIX" '
    walk(
      if type == "object" and has("command")
      then .command |= (ltrimstr($p1) | ltrimstr($p2))
      else .
      end
    )
  ' "$1"
}

@test "hooks-config-sync: both hook config files are valid JSON" {
  jq empty "$FRAGMENT"
  jq empty "$PLUGIN"
}

@test "hooks-config-sync: every fragment command uses the .claude/hooks/ prefix" {
  run jq -r --arg p "$FRAGMENT_PREFIX" \
    '[.. | objects | select(has("command")) | .command | select(startswith($p) | not)] | length' \
    "$FRAGMENT"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "hooks-config-sync: every plugin command uses the CLAUDE_PLUGIN_ROOT/scripts/ prefix" {
  run jq -r --arg p "$PLUGIN_PREFIX" \
    '[.. | objects | select(has("command")) | .command | select(startswith($p) | not)] | length' \
    "$PLUGIN"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "hooks-config-sync: fragment and plugin hooks are identical after prefix normalization" {
  run diff <(normalize "$FRAGMENT") <(normalize "$PLUGIN")
  if [ "$status" -ne 0 ]; then
    echo "settings/hooks.fragment.json and plugins/claudness/hooks/hooks.json have drifted:"
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}
