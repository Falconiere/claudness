#!/usr/bin/env bats
# The SessionStart mandatory-proactive-tool-use block: when the comemory /
# ast-grep plugins are installed (per the registry) AND their binary is on
# PATH, session-start must emit a hard, non-optional mandate to use them
# proactively. Absent the plugin (registry parsed, spec not present), no
# mandate. Drives the REAL entrypoint with a synthetic installed-plugins
# registry; binary presence is real (skips when the tool is not installed).

setup() {
  PLUGINS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  ENTRY="$PLUGINS_DIR/claudness/hooks/session-start.sh"
  TMP=$(mktemp -d)
  REG="$TMP/installed_plugins.json"
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

# Run session-start from an empty dir (no claudness manifest in PROJECT_ROOT,
# so the dep-warning block stays quiet) with a synthetic plugins registry.
_run_entry() {
  ( cd "$TMP" && env CLAUDE_PLUGINS_REGISTRY="$REG" HOME="$TMP" \
      bash "$ENTRY" <<<'{"hook_event_name":"SessionStart","source":"startup"}' )
}

@test "mandate: comemory plugin installed + binary present emits a proactive recall/save mandate" {
  command -v comemory >/dev/null 2>&1 || skip "comemory binary not installed"
  printf '%s' '{"plugins":{"comemory@falconiere":{}}}' > "$REG"
  run _run_entry
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "MANDATORY"
  echo "$output" | grep -q 'comemory.sh search'
  echo "$output" | grep -q "do NOT ask permission"
}

@test "mandate: ast-grep plugin installed + binary present emits a structural-search mandate" {
  command -v ast-grep >/dev/null 2>&1 || command -v sg >/dev/null 2>&1 || skip "ast-grep binary not installed"
  printf '%s' '{"plugins":{"ast-grep@falconiere":{}}}' > "$REG"
  run _run_entry
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "MANDATORY"
  echo "$output" | grep -q 'ast-grep run --pattern'
  echo "$output" | grep -q "FALLBACK ONLY"
}

@test "mandate: no comemory mandate when the plugin is definitively absent" {
  printf '%s' '{"plugins":{}}' > "$REG"
  run _run_entry
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'comemory.sh search'
}

@test "mandate: no ast-grep mandate when the plugin is definitively absent" {
  printf '%s' '{"plugins":{}}' > "$REG"
  run _run_entry
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'ast-grep run --pattern'
}

@test "mandate: both plugins installed emit both mandates under one MANDATORY header" {
  command -v comemory >/dev/null 2>&1 || skip "comemory binary not installed"
  command -v ast-grep >/dev/null 2>&1 || command -v sg >/dev/null 2>&1 || skip "ast-grep binary not installed"
  printf '%s' '{"plugins":{"comemory@falconiere":{},"ast-grep@falconiere":{}}}' > "$REG"
  run _run_entry
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c "MANDATORY — proactive plugin use")" -eq 1 ]
  echo "$output" | grep -q 'comemory.sh search'
  echo "$output" | grep -q 'ast-grep run --pattern'
  # Mandates propagate to nested subagents.
  echo "$output" | grep -q "Propagation"
  echo "$output" | grep -q "bind EVERY agent"
}

@test "mandate: indeterminate registry fails open — mandate still fires when binary present" {
  command -v comemory >/dev/null 2>&1 || skip "comemory binary not installed"
  rm -f "$REG"   # registry absent → claudness_plugin_active fails open
  run _run_entry
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'comemory.sh search'
}
