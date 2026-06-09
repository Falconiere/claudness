#!/usr/bin/env bats
# Tests for hooks/pre-tools/modules/quality-gate.sh

HOOK="${BATS_TEST_DIRNAME}/../quality-gate.sh"

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  mkdir -p .claude/tmp
  printf '%s\n' '{"status":"failing","reason":"forced","violations":""}' > .claude/tmp/quality-gate-status.json
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "quality-gate: exits 0 with MY_CLAUDE_QUALITY=off" {
  payload='{"tool_input":{"command":"rm -rf /"}}'
  MY_CLAUDE_QUALITY=off tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "quality-gate: exits 0 in a barebones repo with no toolchain (no detected pm + no cargo blocks nothing extra)" {
  # No state file → exit 0 regardless of toolchain.
  rm -f .claude/tmp/quality-gate-status.json
  payload='{"tool_input":{"command":"echo hi"}}'
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Regression: extra_pattern (vitest|tsc|...) was unanchored, so
# `cat tsconfig.json` bypassed the failing gate via the `tsc` substring.
@test "quality-gate: 'cat tsconfig.json' is DENIED during failing gate (substring match no longer bypasses)" {
  payload=$(jq -n '{tool_input:{command:"cat tsconfig.json"}}')
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

# Regression: main allow_pattern was unanchored, so a destructive prefix
# could ride along with an allowed allow_pattern command.
@test "quality-gate: 'rm -rf node_modules && bun run check' is DENIED during failing gate" {
  # Make sure bun is detected (need bun.lock).
  touch bun.lock
  payload=$(jq -n '{tool_input:{command:"rm -rf node_modules && bun run check"}}')
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  # The denylist must apply: rm comes first as the start-of-statement command,
  # bun run check riding behind && is NOT a free pass.
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

# Regression: `git commit` was in the failing-gate allowlist, defeating the
# gate's stated purpose.
@test "quality-gate: 'git commit -m \"wip\"' is DENIED during failing gate" {
  payload=$(jq -n '{tool_input:{command:"git commit -m \"wip\""}}')
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "quality-gate: 'bun run check' (alone) is ALLOWED during failing gate" {
  touch bun.lock
  payload=$(jq -n '{tool_input:{command:"bun run check"}}')
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "quality-gate: 'git status' is ALLOWED during failing gate" {
  payload=$(jq -n '{tool_input:{command:"git status"}}')
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Regression: allow_pattern components are joined with `|` at top level.
# Without an outer group, ANCHOR_PREFIX binds only to the FIRST component and
# ANCHOR_SUFFIX only to the LAST — middle components (e.g. the cargo pattern
# in a bun+rust repo) matched anywhere in the string, letting a destructive
# prefix ride along.
@test "quality-gate: 'rm -rf src && cargo fmt' is DENIED in a bun+rust repo (middle component stays anchored)" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  touch bun.lock Cargo.toml
  payload=$(jq -n '{tool_input:{command:"rm -rf src && cargo fmt"}}')
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "quality-gate: 'cargo fmt' (alone) is ALLOWED in a bun+rust repo" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  command -v cargo >/dev/null 2>&1 || skip "cargo not installed"
  touch bun.lock Cargo.toml
  payload=$(jq -n '{tool_input:{command:"cargo fmt"}}')
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Compositional allow case: an allowed first statement + trailing composition.
@test "quality-gate: 'bun run check && bun run build' allowed (first statement matches)" {
  touch bun.lock
  payload=$(jq -n '{tool_input:{command:"bun run check && bun run build"}}')
  tool_name=Bash input="$payload" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
