#!/usr/bin/env bats
# Tests for the code-intel plugin's engram-scope.sh registry module.

HOOK="${BATS_TEST_DIRNAME}/../engram-scope.sh"

# Core lib lives in the sibling claudness plugin; the dispatcher provides
# this env var in production, the tests provide it here.
CLAUDNESS_LIB_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../claudness/hooks/lib" && pwd)"
export CLAUDNESS_LIB_DIR

_mk() {
  jq -n --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'
}

_decision() {
  if [[ -z "$1" ]]; then
    echo "allow"
    return
  fi
  echo "$1" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo "allow"
}

@test "engram-scope: non-Bash tool exits silently" {
  payload=$(_mk 'engram search foo')
  run bash -c "tool_name=Edit input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "engram-scope: bare engram search is denied" {
  payload=$(_mk 'engram search foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "engram-scope: bare engram save is denied" {
  payload=$(_mk 'engram save title body')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "engram-scope: bare engram context is denied" {
  payload=$(_mk 'engram context')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "engram-scope: bare engram summary is denied" {
  payload=$(_mk 'engram summary "session note"')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "engram-scope: engram search with --project is allowed" {
  payload=$(_mk 'engram search foo --project claudness')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: engram save with -p shorthand is allowed" {
  payload=$(_mk 'engram save a b -p claudness')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: wrapper call is allowed" {
  payload=$(_mk 'skills/code-intel/scripts/mod.sh engram search foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: engram stats is allowed (global by design)" {
  payload=$(_mk 'engram stats')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: engram timeline by id is allowed" {
  payload=$(_mk 'engram timeline 42 --before 3')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: ENGRAM_PROJECT= env-prefix counts as scope" {
  payload=$(_mk 'ENGRAM_PROJECT=x engram search foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

# Regression: env-prefix strip regex stopped the value at the first space, so
# a quoted env value with whitespace (MY_VAR="foo bar") left the tail
# (bar" engram save) unmatched by the ^engram check — an unscoped raw call
# slipped through. A quoted value must be consumed whole, leaving `engram save`
# as the segment, which is then denied for missing scope.
@test "engram-scope: quoted env value with whitespace before bare engram save is denied" {
  payload=$(_mk 'MY_VAR="foo bar" engram save title body')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

# Regression: lowercase env-var prefixes (foo=bar engram …) are legal in bash.
# The strip regex only matched uppercase NAME chars, so the lowercase prefix was
# left in place and the segment no longer matched ^engram — the unscoped raw
# call slipped through. Widening the NAME class keeps it denied.
@test "engram-scope: lowercase env prefix before bare engram save is denied" {
  payload=$(_mk 'foo=bar engram save title body')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "engram-scope: chained — bare engram search after && is denied" {
  payload=$(_mk 'ls && engram search foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "engram-scope: engram conflicts show <id> is allowed" {
  payload=$(_mk 'engram conflicts show 42')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: engram conflicts list without --project is denied" {
  payload=$(_mk 'engram conflicts list')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "engram-scope: engram conflicts stats without --project is denied" {
  payload=$(_mk 'engram conflicts stats')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "engram-scope: engram conflicts list with --project is allowed" {
  payload=$(_mk 'engram conflicts list --project foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: bare engram with no subcommand is allowed (will fail at CLI)" {
  payload=$(_mk 'engram')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: deny message mentions wrapper path" {
  payload=$(_mk 'engram search foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("mod.sh engram")'
}

@test "engram-scope: semicolon inside quoted save arg does not falsely deny" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  payload=$(_mk 'engram save "title; with semicolon" body --project foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: double-quoted &&  inside arg does not split" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  payload=$(_mk 'engram save "a && b" body --project foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "engram-scope: module ships in the plugin's pre-tools.d source dir" {
  # The module no longer lives in core's modules/ glob — it reaches the
  # dispatcher via the runtime registry (register.sh sync). This asserts the
  # source-of-truth location register.sh mirrors.
  [ -f "${BATS_TEST_DIRNAME}/../engram-scope.sh" ]
}

@test "engram-scope: exits 0 silently when CLAUDNESS_LIB_DIR is unset (fail soft)" {
  payload=$(_mk 'engram search foo')
  run env -u CLAUDNESS_LIB_DIR tool_name=Bash input="$payload" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
