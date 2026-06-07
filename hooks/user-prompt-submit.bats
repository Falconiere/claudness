#!/usr/bin/env bats
# Tests for hooks/user-prompt-submit.sh — must remain project-agnostic.

HOOK="${BATS_TEST_DIRNAME}/user-prompt-submit.sh"

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
}

teardown() {
  cd /tmp
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

build_input() {
  jq -n --arg p "$1" '{prompt: $p}'
}

@test "user-prompt-submit: runs without context.sh present" {
  payload=$(build_input "implement a new feature for the dashboard")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
}

@test "user-prompt-submit: sources .claude/context.sh when present" {
  mkdir -p .claude
  cat > .claude/context.sh <<'CTX'
#!/usr/bin/env bash
echo "CUSTOM_PROJECT_CONTEXT_MARKER"
CTX
  chmod +x .claude/context.sh
  payload=$(build_input "implement a new feature")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CUSTOM_PROJECT_CONTEXT_MARKER"
}

@test "user-prompt-submit: output does not mention yamless or routo" {
  payload=$(build_input "refactor the engine module")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qE 'yamless|routo|/Volumes/Projects/(routo|yamless)'
}

@test "user-prompt-submit: trivial prompt exits without output" {
  payload=$(build_input "yes")
  run bash "$HOOK" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
