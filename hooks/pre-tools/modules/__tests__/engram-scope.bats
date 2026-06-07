#!/usr/bin/env bats
# Tests for hooks/pre-tools/modules/engram-scope.sh

HOOK="${BATS_TEST_DIRNAME}/../engram-scope.sh"

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
  payload=$(_mk '.claude/skills/code-intel/scripts/mod.sh engram search foo')
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

@test "engram-scope: dispatcher picks up the module by glob" {
  shopt -s nullglob
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  modules=("$REPO_ROOT"/hooks/pre-tools/modules/*.sh)
  found=0
  for m in "${modules[@]}"; do
    [[ "$m" == *engram-scope.sh ]] && found=1
  done
  [ "$found" -eq 1 ]
}
