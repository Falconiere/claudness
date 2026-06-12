#!/usr/bin/env bats
# Tests for the code-intel plugin's comemory-scope.sh registry module.

HOOK="${BATS_TEST_DIRNAME}/../comemory-scope.sh"

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

@test "comemory-scope: non-Bash tool exits silently" {
  payload=$(_mk 'comemory search foo')
  run bash -c "tool_name=Edit input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "comemory-scope: bare comemory search is denied" {
  payload=$(_mk 'comemory search "x"')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "comemory-scope: bare comemory save is denied" {
  payload=$(_mk 'comemory save body --kind note')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "comemory-scope: bare comemory context is denied" {
  payload=$(_mk 'comemory context query')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "comemory-scope: comemory search with --repo is allowed" {
  payload=$(_mk 'comemory search "x" --repo claudness')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "comemory-scope: comemory save with --repo is allowed" {
  payload=$(_mk 'comemory save body --kind note --repo claudness')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "comemory-scope: comemory search with --repo= form is allowed" {
  payload=$(_mk 'comemory search "x" --repo=claudness')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "comemory-scope: wrapper call is allowed (bypass)" {
  payload=$(_mk 'skills/code-intel/scripts/mod.sh comemory search "x"')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "comemory-scope: comemory list is allowed (global by design)" {
  payload=$(_mk 'comemory list --repo claudness')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "comemory-scope: comemory doctor is allowed (global by design)" {
  payload=$(_mk 'comemory doctor')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "comemory-scope: comemory stats is allowed (global by design)" {
  payload=$(_mk 'comemory stats')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

# An env prefix is NOT scope for comemory (no repo env var) — the bare
# `comemory search` underneath must still be denied for missing --repo.
@test "comemory-scope: env prefix before bare comemory search is denied" {
  payload=$(_mk 'FOO=x comemory search "x"')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

# Regression: env-prefix strip regex stopped the value at the first space, so
# a quoted env value with whitespace (MY_VAR="foo bar") left the tail
# (bar" comemory save) unmatched by the ^comemory check — an unscoped raw call
# slipped through. A quoted value must be consumed whole, leaving `comemory
# save` as the segment, which is then denied for missing scope.
@test "comemory-scope: quoted env value with whitespace before bare comemory save is denied" {
  payload=$(_mk 'MY_VAR="foo bar" comemory save body --kind note')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

# Regression: lowercase env-var prefixes (foo=bar comemory …) are legal in bash.
# The strip regex only matched uppercase NAME chars, so the lowercase prefix was
# left in place and the segment no longer matched ^comemory — the unscoped raw
# call slipped through. Widening the NAME class keeps it denied.
@test "comemory-scope: lowercase env prefix before bare comemory save is denied" {
  payload=$(_mk 'foo=bar comemory save body --kind note')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "comemory-scope: chained — bare comemory search after && is denied" {
  payload=$(_mk 'ls && comemory search "x"')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "deny" ]
}

@test "comemory-scope: bare comemory with no subcommand is allowed (will fail at CLI)" {
  payload=$(_mk 'comemory')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "comemory-scope: deny message mentions wrapper path" {
  payload=$(_mk 'comemory search "x"')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("mod.sh comemory")'
}

@test "comemory-scope: semicolon inside quoted save arg does not falsely deny" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  payload=$(_mk 'comemory save "title; with semicolon" --kind note --repo foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "comemory-scope: double-quoted &&  inside arg does not split" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  payload=$(_mk 'comemory save "a && b" --kind note --repo foo')
  run bash -c "tool_name=Bash input='$payload' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(_decision "$output")" = "allow" ]
}

@test "comemory-scope: module ships in the plugin's pre-tools.d source dir" {
  # The module no longer lives in core's modules/ glob — it reaches the
  # dispatcher via the runtime registry (register.sh sync). This asserts the
  # source-of-truth location register.sh mirrors.
  [ -f "${BATS_TEST_DIRNAME}/../comemory-scope.sh" ]
}

@test "comemory-scope: exits 0 silently when CLAUDNESS_LIB_DIR is unset (fail soft)" {
  payload=$(_mk 'comemory search "x"')
  run env -u CLAUDNESS_LIB_DIR tool_name=Bash input="$payload" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
